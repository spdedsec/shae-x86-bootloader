; ==============================================================================
; SHAE x86 Bootloader - Stage 1 (Master Boot Record / Sector 1)
; ==============================================================================
; Architecture: x86 (16-bit Real Mode)
; Origin:       0x7C00 (Standard BIOS load address)
; Size:         Exactly 512 bytes with 0xAA55 signature
; Purpose:      Initialize CPU segments, detect BIOS disk extensions, load
;               Stage 2 from disk into memory at 0x8000, verify its magic
;               signature, and jump to Stage 2.
; ==============================================================================

[BITS 16]
[ORG 0x7C00]

%include "include/boot.inc"

; ------------------------------------------------------------------------------
; Entry Point & BIOS Parameter Block (BPB)
; ------------------------------------------------------------------------------
; Standard short jump and NOP required for FAT filesystem compatibility
entry:
    jmp short start
    nop

; ------------------------------------------------------------------------------
; BIOS Parameter Block (FAT12/16 Dummy Header)
; Prevents modern BIOSes or formatting tools from overwriting bootloader code
; ------------------------------------------------------------------------------
bpb_oem_name:           db "SHAEBOOT"       ; 8 bytes OEM identifier
bpb_bytes_per_sector:   dw 512              ; Bytes per logical sector
bpb_sectors_per_cluster:db 1                ; Sectors per cluster
bpb_reserved_sectors:   dw 1                ; Reserved sectors (MBR)
bpb_num_fats:           db 2                ; Number of File Allocation Tables
bpb_root_entries:       dw 224              ; Max entries in root directory
bpb_total_sectors_16:   dw 2880             ; Total sectors (1.44MB floppy dummy)
bpb_media_descriptor:   db 0xF0             ; Media descriptor (floppy/disk)
bpb_sectors_per_fat:    dw 9                ; Sectors per FAT
bpb_sectors_per_track:  dw 18               ; Sectors per track (geometry)
bpb_num_heads:          dw 2                ; Number of heads (geometry)
bpb_hidden_sectors:     dd 0                ; Hidden sectors
bpb_total_sectors_32:   dd 0                ; Large sector count

; Extended Boot Record (EBR)
ebr_drive_number:       db 0x80             ; Drive number (0x80 = first hard disk)
ebr_reserved:           db 0                ; Reserved / Windows NT flags
ebr_signature:          db 0x29             ; Extended boot signature
ebr_volume_id:          dd 0x19940824       ; Volume serial number
ebr_volume_label:       db "SHAE BOOT  "    ; 11 bytes volume label
ebr_system_id:          db "FAT12   "       ; 8 bytes filesystem type string

; ------------------------------------------------------------------------------
; Stage 1 Main Execution Logic
; ------------------------------------------------------------------------------
start:
    ; Step 1: Disable interrupts while setting up critical segment registers
    cli

    ; Step 2: Normalize segment registers to 0x0000 (flat real mode)
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Step 3: Establish a safe real-mode stack growing downwards from 0x7C00
    mov ss, ax
    mov sp, STAGE1_STACK_TOP

    ; Step 4: Re-enable interrupts now that stack is safely initialized
    sti

    ; Step 5: Save BIOS boot drive number passed in DL register
    mov [boot_drive], dl

    ; Step 6: Print Stage 1 welcome message
    mov si, msg_stage1
    call print_string_rm

    ; Step 7: Load Stage 2 from disk into RAM at STAGE2_LOAD_ADDR (0x8000)
    call load_stage2

    ; Step 8: Verify Stage 2 magic signature ("SHAE" = 0x53484145)
    mov eax, [STAGE2_LOAD_ADDR]
    cmp eax, STAGE2_MAGIC
    jne .stage2_corrupt

    ; Step 9: Jump to Stage 2 entry point (skipping the 4-byte magic signature)
    ; Pass boot drive in DL to Stage 2
    mov dl, [boot_drive]
    jmp 0x0000:(STAGE2_LOAD_ADDR + 4)

.stage2_corrupt:
    mov si, err_stage2_sig
    call print_string_rm
    jmp halt_system

; ------------------------------------------------------------------------------
; Routine: load_stage2
; Loads Stage 2 from the boot drive into memory at 0x0000:0x8000.
; Attempts INT 13h Extension (LBA Packet Read) first; falls back to CHS.
; ------------------------------------------------------------------------------
load_stage2:
    mov byte [retry_count], 3        ; Allow up to 3 read retries

.check_lba:
    ; Test if INT 13h extensions (LBA packet reads) are supported
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc .fallback_chs                 ; Carry set -> extensions not supported
    cmp bx, 0xAA55
    jne .fallback_chs                ; Magic value mismatch -> use CHS
    test cx, 1
    jz .fallback_chs                 ; Bit 0 clear -> extended disk access not supported

.read_lba:
    ; Setup and execute LBA packet read (AH=0x42)
    mov si, dap                      ; DS:SI points to Disk Address Packet
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jnc .read_success                ; Success if Carry flag is clear

    ; Read error: decrement retry counter and retry
    dec byte [retry_count]
    jz .disk_error

    ; Reset disk system (AH=0x00)
    xor ax, ax
    mov dl, [boot_drive]
    int 0x13
    jmp .read_lba

.fallback_chs:
    ; Fallback: Traditional CHS disk read (AH=0x02)
    ; Target: 0x0000:0x8000
    ; Cylinder 0, Head 0, Sector 2 (1-indexed)
    mov ax, 0x0000
    mov es, ax
    mov bx, STAGE2_LOAD_ADDR         ; ES:BX = 0x0000:0x8000

    mov ah, 0x02                     ; BIOS Read Sectors function
    mov al, STAGE2_SECTOR_COUNT      ; Number of sectors to read
    mov ch, 0                        ; Cylinder 0
    mov cl, STAGE2_SECTOR_START      ; Sector 2
    mov dh, 0                        ; Head 0
    mov dl, [boot_drive]             ; Boot drive number
    int 0x13
    jnc .read_success

    dec byte [retry_count]
    jz .disk_error

    xor ax, ax                       ; Reset disk controller
    mov dl, [boot_drive]
    int 0x13
    jmp .fallback_chs

.read_success:
    ret

.disk_error:
    mov si, err_disk_read
    call print_string_rm
    jmp halt_system

; ------------------------------------------------------------------------------
; Routine: print_string_rm
; Prints a null-terminated string to screen using BIOS INT 10h Teletype (AH=0x0E)
; Input: DS:SI -> Null-terminated ASCII string
; ------------------------------------------------------------------------------
print_string_rm:
    push ax
    push bx
    push si
    mov ah, 0x0E                     ; BIOS teletype output
    mov bh, 0x00                     ; Page number 0
    mov bl, 0x07                     ; Standard light gray attribute
.loop:
    lodsb                            ; AL = [DS:SI++]
    test al, al
    jz .done
    int 0x10                         ; Video BIOS interrupt
    jmp .loop
.done:
    pop si
    pop bx
    pop ax
    ret

; ------------------------------------------------------------------------------
; Routine: halt_system
; Halts CPU indefinitely when an unrecoverable boot error occurs
; ------------------------------------------------------------------------------
halt_system:
    mov si, msg_halted
    call print_string_rm
.hang:
    cli
    hlt
    jmp .hang

; ------------------------------------------------------------------------------
; Data & Disk Address Packet (DAP)
; ------------------------------------------------------------------------------
align 4
dap:
    db 0x10                          ; DAP size = 16 bytes
    db 0x00                          ; Reserved (always 0)
    dw STAGE2_SECTOR_COUNT           ; Number of sectors to transfer
    dw STAGE2_LOAD_ADDR              ; Destination memory offset (0x8000)
    dw 0x0000                        ; Destination memory segment (0x0000)
    dq 1                             ; Starting LBA (Sector 1 = 2nd sector on disk)

boot_drive:     db 0x00
retry_count:    db 0x03

msg_stage1:     db "[SHAE] Stage 1 MBR loading Stage 2...", 13, 10, 0
err_disk_read:  db "Disk error!", 13, 10, 0
err_stage2_sig: db "Bad Stage 2 signature!", 13, 10, 0
msg_halted:     db "Halted.", 13, 10, 0

times 510 - ($ - $$) db 0
dw MBR_MAGIC
