; ==============================================================================
; SHAE x86 Bootloader - C Kernel Payload Entry Stub
; ==============================================================================

[BITS 32]
section .entry
global _start
extern c_kernel_main

_start:
    ; Parameters passed in registers from SHAE Bootloader:
    ; EAX = E820 Memory Map Count
    ; EBX = E820 Memory Map Address (0x7E08)
    push ebx
    push eax
    call c_kernel_main
    add esp, 8
    ret
