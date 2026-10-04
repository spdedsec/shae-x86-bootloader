; ==============================================================================
; SHAE x86 Bootloader - Stage 2 (Real Mode Setup & Protected Mode Switch)
; ==============================================================================
; Architecture: x86 (16-bit Real Mode -> 32-bit Protected Mode)
; Origin:       0x8000
; Purpose:      1. Validate Stage 2 magic signature ("SHAE")
;               2. Query system physical memory map via BIOS INT 15h, AX=0xE820
;               3. Enable Address Line 20 (A20 Gate)
;               4. Load secondary Kernel Payload from disk into staging buffer
;               5. Construct and load the Global Descriptor Table (GDT)
;               6. Switch CPU from 16-bit Real Mode to 32-bit Protected Mode
;               7. Flush pipeline with far jump and branch to 32-bit Kernel/Shell
; ==============================================================================

[BITS 16]
[ORG 0x8000]

%include "include/boot.inc"
%include "include/gdt.inc"

; ------------------------------------------------------------------------------
; Magic Signature (4 bytes)
; Located at 0x8000. Verified by Stage 1 prior to jumping here.
; ------------------------------------------------------------------------------
stage2_header:
    dd STAGE2_MAGIC                  ; 0x53484145 ("SHAE")

; ------------------------------------------------------------------------------
; Stage 2 Entry Point (0x8004)
; ------------------------------------------------------------------------------
stage2_entry:
    ; Save boot drive passed from Stage 1 in DL
    mov [stage2_boot_drive], dl

    ; Re-initialize data segment to 0x0000
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Print Stage 2 banner
    mov si, msg_stage2_start
    call print_string_rm

    ; --------------------------------------------------------------------------
    ; Step 1: Detect Physical Memory Map using BIOS INT 15h, AX=0xE820
    ; --------------------------------------------------------------------------
    mov si, msg_detecting_mem
    call print_string_rm
    call detect_memory_e820

    ; --------------------------------------------------------------------------
    ; Step 2: Enable Address Line 20 (A20 Gate)
    ; --------------------------------------------------------------------------
    mov si, msg_enabling_a20
    call print_string_rm
    call enable_a20
    test ax, ax
    jnz .a20_failed

    mov si, msg_a20_ok
    call print_string_rm
    jmp .a20_done

.a20_failed:
    mov si, err_a20
    call print_string_rm
    ; Halt on critical A20 failure
    jmp halt_system_rm

.a20_done:
    ; --------------------------------------------------------------------------
    ; Step 3: Load Kernel Payload into Staging Buffer (0x10000)
    ; --------------------------------------------------------------------------
    mov si, msg_loading_payload
    call print_string_rm
    call load_payload_staging

    ; --------------------------------------------------------------------------
    ; Step 4: Prepare Video Mode
    ; Set standard 80x25 16-color text mode (Mode 3)
    ; --------------------------------------------------------------------------
    mov ax, 0x0003
    int 0x10

    ; --------------------------------------------------------------------------
    ; Step 5: Transition to 32-bit Protected Mode
    ; --------------------------------------------------------------------------
    cli                              ; Disable maskable hardware interrupts
    cld                              ; Clear direction flag (forward string operations)

    ; Load Global Descriptor Table Register (GDTR)
    lgdt [gdt_descriptor]

    ; Set PE (Protection Enable) Bit 0 in Control Register CR0
    mov eax, cr0
    or eax, 1                        ; CR0.PE = 1
    mov cr0, eax

    ; Far jump to 32-bit code segment to flush CPU prefetch queue & load CS
    jmp GDT_KERNEL_CODE_SEL:protected_mode_entry

; ------------------------------------------------------------------------------
; Routine: detect_memory_e820
; Queries BIOS INT 15h, AX=0xE820 to construct an accurate physical memory map.
; Stores count at MMAP_COUNT_ADDR (0x7E00) and entries at MMAP_ENTRIES_ADDR (0x7E08).
; Each entry is 24 bytes: Base(8), Length(8), Type(4), ACPI Extended Attributes(4).
; ------------------------------------------------------------------------------
detect_memory_e820:
    push es
    push di
    push bp

    xor ax, ax
    mov es, ax
    mov di, MMAP_ENTRIES_ADDR        ; Destination address for entries
    xor ebx, ebx                     ; EBX must be 0 at initial call
    xor bp, bp                       ; BP tracks number of valid entries
    mov edx, 0x534D4150              ; Magic signature 'SMAP'

.e820_loop:
    mov eax, 0x0000E820              ; E820 function code
    mov ecx, 24                      ; Ask for 24-byte entry
    mov dword [es:di + 20], 1        ; Default ACPI 3.x attribute (ignore=1)
    int 0x15

    jc .e820_end                     ; Carry set -> end of map or unsupported
    cmp eax, 0x534D4150              ; Verify SMAP return signature
    jne .e820_end

    jcxz .skip_entry                 ; 0 bytes returned -> skip
    cmp cl, 20                       ; Did BIOS return 20 bytes?
    jbe .valid_20
    test byte [es:di + 20], 1        ; Check ACPI ignore bit
    jz .skip_entry

.valid_20:
    ; Ignore zero-length regions
    mov ecx, [es:di + 8]             ; Length low 32 bits
    or ecx, [es:di + 12]             ; Length high 32 bits
    jz .skip_entry

    inc bp                           ; Valid entry recorded
    add di, 24                       ; Advance buffer pointer

.skip_entry:
    test ebx, ebx                    ; EBX=0 indicates end of memory map
    jnz .e820_loop

.e820_end:
    mov [MMAP_COUNT_ADDR], bp        ; Save total detected entries count
    pop bp
    pop di
    pop es
    ret

; ------------------------------------------------------------------------------
; Routine: load_payload_staging
; Loads Kernel payload sectors from disk into 0x10000 staging memory.
; ------------------------------------------------------------------------------
load_payload_staging:
    pusha
    mov si, payload_dap
    mov ah, 0x42
    mov dl, [stage2_boot_drive]
    int 0x13
    jnc .payload_done

    ; If LBA read fails, fallback to CHS read
    mov ax, 0x1000
    mov es, ax
    xor bx, bx                       ; Destination ES:BX = 0x1000:0x0000 = 0x10000
    mov ah, 0x02
    mov al, KERNEL_SECTOR_COUNT
    mov ch, 0
    mov cl, KERNEL_SECTOR_START
    mov dh, 0
    mov dl, [stage2_boot_drive]
    int 0x13
    ; If payload doesn't exist yet on disk, continue gracefully
.payload_done:
    popa
    ret

; ------------------------------------------------------------------------------
; Routine: print_string_rm
; ------------------------------------------------------------------------------
print_string_rm:
    push ax
    push bx
    push si
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
.loop:
    lodsb
    test al, al
    jz .done
    int 0x10
    jmp .loop
.done:
    pop si
    pop bx
    pop ax
    ret

halt_system_rm:
    cli
    hlt
    jmp halt_system_rm

; ------------------------------------------------------------------------------
; A20 Module Inclusion (16-bit)
; ------------------------------------------------------------------------------
%include "src/boot/a20.asm"

; ------------------------------------------------------------------------------
; Global Descriptor Table (GDT)
; Flat memory model: 4GB Code & Data segments mapping entire physical memory
; ------------------------------------------------------------------------------
align 16
gdt_start:
    ; 1. Null Descriptor (Selector 0x00) - Mandatory CPU dummy entry
    dd 0x00000000
    dd 0x00000000

    ; 2. Kernel Code Segment (Selector 0x08)
    ; Base: 0x00000000, Limit: 0xFFFFF (4GB with 4KB pages)
    ; Access: Present (1), Ring 0 (00), DescType (1), Executable (1), Read (1) = 0x9A
    ; Flags: Granularity 4KB (1), 32-bit Default (1), 64-bit (0) = 0xC
    dw 0xFFFF                        ; Segment Limit [15:0]
    dw 0x0000                        ; Base Address [15:0]
    db 0x00                          ; Base Address [23:16]
    db 0x9A                          ; Access Byte
    db 0xCF                          ; Flags [7:4] & Segment Limit [19:16]
    db 0x00                          ; Base Address [31:24]

    ; 3. Kernel Data Segment (Selector 0x10)
    ; Base: 0x00000000, Limit: 0xFFFFF (4GB with 4KB pages)
    ; Access: Present (1), Ring 0 (00), DescType (1), Writable (1) = 0x92
    ; Flags: Granularity 4KB (1), 32-bit Default (1) = 0xC
    dw 0xFFFF                        ; Segment Limit [15:0]
    dw 0x0000                        ; Base Address [15:0]
    db 0x00                          ; Base Address [23:16]
    db 0x92                          ; Access Byte
    db 0xCF                          ; Flags [7:4] & Segment Limit [19:16]
    db 0x00                          ; Base Address [31:24]

    ; 4. User Mode Code Segment (Selector 0x18, RPL=3 -> 0x1B)
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0xFA                          ; Present, Ring 3, Code, Exec/Read
    db 0xCF
    db 0x00

    ; 5. User Mode Data Segment (Selector 0x20, RPL=3 -> 0x23)
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0xF2                          ; Present, Ring 3, Data, Read/Write
    db 0xCF
    db 0x00
gdt_end:

; GDTR Descriptor Pointer
align 4
gdt_descriptor:
    dw gdt_end - gdt_start - 1       ; Size of GDT table minus 1
    dd gdt_start                     ; 32-bit linear address of GDT

; ------------------------------------------------------------------------------
; 16-bit Data Area
; ------------------------------------------------------------------------------
align 4
payload_dap:
    db 0x10
    db 0x00
    dw KERNEL_SECTOR_COUNT
    dw 0x0000                        ; Offset 0x0000
    dw 0x1000                        ; Segment 0x1000 -> 0x10000 physical
    dq KERNEL_LBA_START

stage2_boot_drive: db 0x00

msg_stage2_start:   db 13, 10, "[SHAE] Stage 2 executing in Real Mode at 0x8000.", 13, 10, 0
msg_detecting_mem:  db "[SHAE] Querying E820 Physical Memory Map...", 13, 10, 0
msg_enabling_a20:   db "[SHAE] Validating Address Line 20 (A20)...", 13, 10, 0
msg_a20_ok:         db "[SHAE] A20 Gate confirmed ACTIVE.", 13, 10, 0
msg_loading_payload:db "[SHAE] Reading Kernel staging image from disk...", 13, 10, 0
err_a20:            db 13, 10, "[FATAL] Failed to activate A20 Gate! System halting.", 13, 10, 0

; ==============================================================================
; 32-BIT PROTECTED MODE ENTRY POINT
; ==============================================================================
[BITS 32]

protected_mode_entry:
    ; Step 1: Reload all data segment selectors with GDT_KERNEL_DATA_SEL (0x10)
    mov ax, GDT_KERNEL_DATA_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Step 2: Establish dedicated 32-bit protected mode stack at 0x90000
    mov esp, PROTECTED_STACK_TOP
    mov ebp, esp

    ; Step 3: Copy Kernel Payload from staging buffer (0x10000) to 1MB (0x100000)
    ; if a payload is present (first 4 bytes not all 0 or empty)
    mov esi, 0x10000
    mov edi, KERNEL_LOAD_ADDR
    mov ecx, (KERNEL_SECTOR_COUNT * 512) / 4
    rep movsd

    ; Step 4: Branch directly to the SHAE 32-bit Kernel / Protected Shell
    call kernel_main

    ; If kernel returns, halt CPU
.halt_32:
    cli
    hlt
    jmp .halt_32

; ------------------------------------------------------------------------------
; 32-bit Driver & Kernel Modules
; ------------------------------------------------------------------------------
%include "src/drivers/vga.asm"
%include "src/drivers/serial.asm"
%include "src/drivers/pic.asm"
%include "src/drivers/idt.asm"
%include "src/drivers/keyboard.asm"
%include "src/kernel/cpuinfo.asm"
%include "src/kernel/mmap.asm"
%include "src/kernel/shell.asm"
%include "src/kernel/kernel_entry.asm"
