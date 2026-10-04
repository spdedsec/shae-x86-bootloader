; ==============================================================================
; SHAE x86 Bootloader - E820 Physical Memory Map Parser & Reporter
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Data Location:0x7E00 (Count word), 0x7E08 (Array of 24-byte E820 entries)
; Purpose:      Parses and displays physical memory regions detected by BIOS,
;               and calculates total usable system RAM.
; ==============================================================================

[BITS 32]

%include "include/boot.inc"

global mmap_print_table
global mmap_get_total_usable_kb

extern kprint
extern kprint_hex32
extern kprint_dec
extern vga_puts
extern vga_put_hex32
extern vga_put_dec

section .data
mmap_header:
    db 13, 10
    db "==================== [E820 PHYSICAL MEMORY MAP] ====================", 13, 10
    db "  #   Base Address        Length              Type", 13, 10
    db " -------------------------------------------------------------------", 13, 10, 0

str_entry_prefix:   db " [", 0
str_entry_mid:      db "] ", 0
str_space:          db "  ", 0
str_newline:        db 13, 10, 0
str_summary:        db 13, 10, "  Total Usable RAM Detected: ", 0
str_kb:             db " KB (approx ", 0
str_mb:             db " MB)", 13, 10, 0
str_no_entries:     db "  [!] No E820 memory map entries found.", 13, 10, 0

; Type Strings
type_usable:        db "Usable RAM (Type 1)", 0
type_reserved:      db "Reserved (Type 2)", 0
type_acpi_rec:      db "ACPI Reclaimable (Type 3)", 0
type_acpi_nvs:      db "ACPI NVS (Type 4)", 0
type_bad:           db "Bad Memory (Type 5)", 0
type_unknown:       db "Reserved/Unknown", 0

section .text

; ------------------------------------------------------------------------------
; Routine: mmap_print_table
; Dumps all detected E820 memory map records in tabular form.
; ------------------------------------------------------------------------------
mmap_print_table:
    pusha

    movzx ecx, word [MMAP_COUNT_ADDR]
    test ecx, ecx
    jnz .has_entries

    mov esi, str_no_entries
    call kprint
    popa
    ret

.has_entries:
    mov esi, mmap_header
    call kprint

    mov esi, MMAP_ENTRIES_ADDR
    xor edx, edx                     ; Index counter (0, 1, 2...)

.entry_loop:
    push ecx
    push edx
    push esi

    ; Print index [#]
    mov esi, str_entry_prefix
    call kprint
    mov eax, edx
    call kprint_dec
    mov esi, str_entry_mid
    call kprint

    pop esi
    push esi

    ; Print Base Address (64-bit): High 32 bits then Low 32 bits
    mov eax, [esi + 4]               ; Base high
    call kprint_hex32
    mov eax, [esi]                   ; Base low
    call kprint_hex32

    mov esi, str_space
    call kprint

    pop esi
    push esi

    ; Print Length (64-bit): High 32 bits then Low 32 bits
    mov eax, [esi + 12]              ; Length high
    call kprint_hex32
    mov eax, [esi + 8]               ; Length low
    call kprint_hex32

    mov esi, str_space
    call kprint

    pop esi
    push esi

    ; Print Type description
    mov eax, [esi + 16]              ; Type dword
    cmp eax, 1
    je .is_usable
    cmp eax, 2
    je .is_reserved
    cmp eax, 3
    je .is_acpi_rec
    cmp eax, 4
    je .is_acpi_nvs
    cmp eax, 5
    je .is_bad

    mov esi, type_unknown
    jmp .print_type

.is_usable:
    mov esi, type_usable
    jmp .print_type
.is_reserved:
    mov esi, type_reserved
    jmp .print_type
.is_acpi_rec:
    mov esi, type_acpi_rec
    jmp .print_type
.is_acpi_nvs:
    mov esi, type_acpi_nvs
    jmp .print_type
.is_bad:
    mov esi, type_bad

.print_type:
    call kprint
    mov esi, str_newline
    call kprint

    pop esi
    pop edx
    pop ecx

    add esi, 24                      ; Advance to next 24-byte entry
    inc edx
    dec ecx
    jnz .entry_loop

    ; Print total RAM calculation
    call mmap_print_summary

    popa
    ret

; ------------------------------------------------------------------------------
; Routine: mmap_get_total_usable_kb
; Computes the total usable memory (Type 1) across all regions in KB.
; Returns: EAX = Total usable RAM in Kilobytes
; ------------------------------------------------------------------------------
mmap_get_total_usable_kb:
    push ebx
    push ecx
    push edx
    push esi

    movzx ecx, word [MMAP_COUNT_ADDR]
    xor ebx, ebx                     ; Total KB accumulator
    mov esi, MMAP_ENTRIES_ADDR

.sum_loop:
    test ecx, ecx
    jz .sum_done

    mov eax, [esi + 16]              ; Type
    cmp eax, 1                       ; Usable RAM?
    jne .skip_region

    ; Length low
    mov eax, [esi + 8]
    ; Length high
    mov edx, [esi + 12]

    ; Convert bytes to KB by dividing by 1024 (shr 10)
    shrd eax, edx, 10
    add ebx, eax

.skip_region:
    add esi, 24
    dec ecx
    jmp .sum_loop

.sum_done:
    mov eax, ebx
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ------------------------------------------------------------------------------
; Routine: mmap_print_summary
; ------------------------------------------------------------------------------
mmap_print_summary:
    mov esi, str_summary
    call kprint

    call mmap_get_total_usable_kb
    push eax
    call kprint_dec

    mov esi, str_kb
    call kprint

    pop eax
    ; Convert KB to MB (divide by 1024)
    shr eax, 10
    call kprint_dec

    mov esi, str_mb
    call kprint
    ret
