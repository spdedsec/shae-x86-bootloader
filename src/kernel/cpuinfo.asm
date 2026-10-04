; ==============================================================================
; SHAE x86 Bootloader - CPUID & Processor Feature Inspector
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Purpose:      Detects CPUID instruction support via EFLAGS bit 21, queries
;               processor vendor, brand model string, and architectural features
;               (FPU, PAE, APIC, MMX, SSE, SSE2, and x86_64 Long Mode support).
; ==============================================================================

[BITS 32]

global cpu_detect
global cpu_print_info

extern kprint
extern kprint_hex32

section .data
vendor_str:     times 13 db 0
brand_str:      times 49 db 0

msg_cpu_header: db 13, 10, "=== [CPU INFORMATION & CAPABILITIES] ===", 13, 10, 0
msg_vendor:     db "  CPU Vendor ID : ", 0
msg_brand:      db "  Processor Name: ", 0
msg_features:   db "  Features Detected:", 13, 10, 0
msg_fpu:        db "    [+] FPU (Floating Point Unit)", 13, 10, 0
msg_tsc:        db "    [+] TSC (Time Stamp Counter)", 13, 10, 0
msg_pae:        db "    [+] PAE (Physical Address Extension)", 13, 10, 0
msg_apic:       db "    [+] APIC (On-chip Advanced PIC)", 13, 10, 0
msg_mmx:        db "    [+] MMX Instructions", 13, 10, 0
msg_sse:        db "    [+] SSE (Streaming SIMD Extensions)", 13, 10, 0
msg_sse2:       db "    [+] SSE2 Extensions", 13, 10, 0
msg_lm:         db "    [+] Long Mode (x86_64 / 64-bit Architecture Ready!)", 13, 10, 0
msg_no_cpuid:   db "  [!] CPUID instruction NOT supported on this CPU.", 13, 10, 0
msg_newline:    db 13, 10, 0

section .text

; ------------------------------------------------------------------------------
; Routine: cpu_has_cpuid
; Tests if the CPU supports the CPUID instruction by toggling EFLAGS ID bit (bit 21).
; Returns: EAX = 1 if supported, EAX = 0 if not supported
; ------------------------------------------------------------------------------
cpu_has_cpuid:
    pushfd
    pushfd
    xor dword [esp], 0x00200000      ; Invert bit 21 (ID flag)
    popfd
    pushfd
    pop eax
    xor eax, [esp]                   ; Compare modified flags with original
    popfd
    and eax, 0x00200000
    shr eax, 21                      ; 1 if bit could be modified, 0 otherwise
    ret

; ------------------------------------------------------------------------------
; Routine: cpu_detect
; Reads Vendor String and Brand String into local buffers.
; ------------------------------------------------------------------------------
cpu_detect:
    call cpu_has_cpuid
    test eax, eax
    jz .done

    ; 1. Query Vendor String (CPUID EAX=0)
    xor eax, eax
    cpuid
    mov [vendor_str], ebx            ; First 4 chars
    mov [vendor_str + 4], edx        ; Next 4 chars
    mov [vendor_str + 8], ecx        ; Last 4 chars
    mov byte [vendor_str + 12], 0    ; Null terminator

    ; 2. Query Extended Functions to check Brand String support
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000004
    jb .no_brand

    ; Query 48-byte Brand String (CPUID 0x80000002, 0x80000003, 0x80000004)
    mov eax, 0x80000002
    cpuid
    mov [brand_str], eax
    mov [brand_str + 4], ebx
    mov [brand_str + 8], ecx
    mov [brand_str + 12], edx

    mov eax, 0x80000003
    cpuid
    mov [brand_str + 16], eax
    mov [brand_str + 20], ebx
    mov [brand_str + 24], ecx
    mov [brand_str + 28], edx

    mov eax, 0x80000004
    cpuid
    mov [brand_str + 32], eax
    mov [brand_str + 36], ebx
    mov [brand_str + 40], ecx
    mov [brand_str + 44], edx
    mov byte [brand_str + 48], 0
    jmp .done

.no_brand:
    mov dword [brand_str], "x86 "
    mov dword [brand_str + 4], "Proc"
    mov dword [brand_str + 8], "esso"
    mov dword [brand_str + 12], "r"
    mov byte [brand_str + 13], 0

.done:
    ret

; ------------------------------------------------------------------------------
; Routine: cpu_print_info
; Outputs formatted CPU information to display and serial console.
; ------------------------------------------------------------------------------
cpu_print_info:
    pusha

    call cpu_has_cpuid
    test eax, eax
    jnz .has_cpuid

    mov esi, msg_no_cpuid
    call kprint
    popa
    ret

.has_cpuid:
    call cpu_detect

    mov esi, msg_cpu_header
    call kprint

    mov esi, msg_vendor
    call kprint
    mov esi, vendor_str
    call kprint
    mov esi, msg_newline
    call kprint

    mov esi, msg_brand
    call kprint
    mov esi, brand_str
    call kprint
    mov esi, msg_newline
    call kprint

    mov esi, msg_features
    call kprint

    ; Query standard features (CPUID EAX=1)
    mov eax, 1
    cpuid

    ; Test EDX feature flags
    test edx, (1 << 0)               ; FPU
    jz .check_tsc
    mov esi, msg_fpu
    call kprint

.check_tsc:
    test edx, (1 << 4)               ; TSC
    jz .check_pae
    mov esi, msg_tsc
    call kprint

.check_pae:
    test edx, (1 << 6)               ; PAE
    jz .check_apic
    mov esi, msg_pae
    call kprint

.check_apic:
    test edx, (1 << 9)               ; APIC
    jz .check_mmx
    mov esi, msg_apic
    call kprint

.check_mmx:
    test edx, (1 << 23)              ; MMX
    jz .check_sse
    mov esi, msg_mmx
    call kprint

.check_sse:
    test edx, (1 << 25)              ; SSE
    jz .check_sse2
    mov esi, msg_sse
    call kprint

.check_sse2:
    test edx, (1 << 26)              ; SSE2
    jz .check_lm
    mov esi, msg_sse2
    call kprint

.check_lm:
    ; Query extended features (CPUID EAX=0x80000001) for Long Mode
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .done_features

    mov eax, 0x80000001
    cpuid
    test edx, (1 << 29)              ; Long Mode (x86_64) bit
    jz .done_features
    mov esi, msg_lm
    call kprint

.done_features:
    popa
    ret
