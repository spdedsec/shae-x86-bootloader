; ==============================================================================
; SHAE x86 Bootloader - Interrupt Descriptor Table (IDT) & Exception Gates
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Purpose:      Initializes the 256-entry IDT, installs ISR handlers for CPU
;               exceptions 0-31 to prevent triple faults, and provides diagnostic
;               panic screens when an exception occurs.
; ==============================================================================

[BITS 32]

global idt_init
global idt_set_gate

extern kprint
extern kprint_hex32
extern vga_set_color
extern vga_puts
extern vga_clear

; Structure of an IDT Gate (8 bytes)
; Bytes 0-1: Offset low (15..0)
; Bytes 2-3: Code Segment Selector (0x08)
; Byte 4:    Reserved (0)
; Byte 5:    Type & Attributes (0x8E = 32-bit Interrupt Gate, Ring 0, Present)
; Bytes 6-7: Offset high (31..16)

IDT_ATTR_INTERRUPT_GATE equ 0x8E

section .bss
align 16
idt_entries:
    resb 256 * 8                     ; 256 gates * 8 bytes = 2048 bytes

section .data
align 4
idt_descriptor:
    dw (256 * 8) - 1                 ; IDT limit (table size - 1)
    dd idt_entries                   ; Base address of IDT

; Exception Name Strings
exc_msg_0:  db "0x00: Division By Zero (#DE)", 0
exc_msg_1:  db "0x01: Debug Exception (#DB)", 0
exc_msg_2:  db "0x02: Non-Maskable Interrupt (NMI)", 0
exc_msg_3:  db "0x03: Breakpoint (#BP)", 0
exc_msg_4:  db "0x04: Overflow (#OF)", 0
exc_msg_5:  db "0x05: Bound Range Exceeded (#BR)", 0
exc_msg_6:  db "0x06: Invalid Opcode (#UD)", 0
exc_msg_7:  db "0x07: Device Not Available (#NM)", 0
exc_msg_8:  db "0x08: Double Fault (#DF)", 0
exc_msg_9:  db "0x09: Coprocessor Segment Overrun", 0
exc_msg_10: db "0x0A: Invalid TSS (#TS)", 0
exc_msg_11: db "0x0B: Segment Not Present (#NP)", 0
exc_msg_12: db "0x0C: Stack-Segment Fault (#SS)", 0
exc_msg_13: db "0x0D: General Protection Fault (#GP)", 0
exc_msg_14: db "0x0E: Page Fault (#PF)", 0
exc_msg_15: db "0x0F: Reserved Exception", 0
exc_msg_16: db "0x10: x87 FPU Floating-Point Error (#MF)", 0
exc_msg_17: db "0x11: Alignment Check (#AC)", 0
exc_msg_18: db "0x12: Machine Check (#MC)", 0
exc_msg_19: db "0x13: SIMD Floating-Point Exception (#XM)", 0
exc_msg_unkn: db "Unknown CPU Trap / Fault", 0

panic_banner:
    db 13, 10
    db "================================================================================", 13, 10
    db "                        FATAL CPU EXCEPTION OCCURRED                            ", 13, 10
    db "================================================================================", 13, 10, 0
panic_halt:
    db 13, 10, "[HALT] CPU halted by SHAE Exception Handler to prevent system corruption.", 13, 10, 0

section .text

; ------------------------------------------------------------------------------
; Routine: idt_init
; Installs exception gates 0..31 and loads the IDTR.
; ------------------------------------------------------------------------------
idt_init:
    push eax
    push ebx
    push ecx

    ; Set default gate for all 256 vectors to unhandled_isr
    xor ecx, ecx
.clear_loop:
    mov eax, ecx
    mov ebx, isr_default
    call idt_set_gate
    inc ecx
    cmp ecx, 256
    jl .clear_loop

    ; Install dedicated handlers for CPU Exceptions 0..19
    mov eax, 0
    mov ebx, isr0
    call idt_set_gate

    mov eax, 1
    mov ebx, isr1
    call idt_set_gate

    mov eax, 2
    mov ebx, isr2
    call idt_set_gate

    mov eax, 3
    mov ebx, isr3
    call idt_set_gate

    mov eax, 4
    mov ebx, isr4
    call idt_set_gate

    mov eax, 5
    mov ebx, isr5
    call idt_set_gate

    mov eax, 6
    mov ebx, isr6
    call idt_set_gate

    mov eax, 7
    mov ebx, isr7
    call idt_set_gate

    mov eax, 8
    mov ebx, isr8
    call idt_set_gate

    mov eax, 9
    mov ebx, isr9
    call idt_set_gate

    mov eax, 10
    mov ebx, isr10
    call idt_set_gate

    mov eax, 11
    mov ebx, isr11
    call idt_set_gate

    mov eax, 12
    mov ebx, isr12
    call idt_set_gate

    mov eax, 13
    mov ebx, isr13
    call idt_set_gate

    mov eax, 14
    mov ebx, isr14
    call idt_set_gate

    mov eax, 16
    mov ebx, isr16
    call idt_set_gate

    mov eax, 17
    mov ebx, isr17
    call idt_set_gate

    mov eax, 18
    mov ebx, isr18
    call idt_set_gate

    mov eax, 19
    mov ebx, isr19
    call idt_set_gate

    ; Load Interrupt Descriptor Table Register (IDTR)
    lidt [idt_descriptor]

    pop ecx
    pop ebx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: idt_set_gate
; Configures a single gate entry in the IDT.
; Input: EAX = Interrupt vector number (0..255)
;        EBX = 32-bit linear address of ISR function
; ------------------------------------------------------------------------------
idt_set_gate:
    push edx
    push edi

    ; Calculate table entry offset: idt_entries + EAX * 8
    mov edi, idt_entries
    lea edi, [edi + eax * 8]

    ; Low 16 bits of offset
    mov word [edi], bx

    ; Segment Selector = 0x08 (Kernel Code)
    mov word [edi + 2], 0x08

    ; Reserved byte = 0
    mov byte [edi + 4], 0

    ; Type and attributes = 0x8E (32-bit Interrupt Gate, Ring 0, Present)
    mov byte [edi + 5], IDT_ATTR_INTERRUPT_GATE

    ; High 16 bits of offset
    shr ebx, 16
    mov word [edi + 6], bx

    pop edi
    pop edx
    ret

; ------------------------------------------------------------------------------
; Common Exception Dispatcher
; ------------------------------------------------------------------------------
exception_common:
    cli
    pusha                            ; Push EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI

    ; Set display color to White on Red for panic screen
    mov al, 0x4F
    call vga_set_color

    mov esi, panic_banner
    call kprint

    ; ESI points to exception name passed before jmp
    popa
    call kprint

    mov esi, panic_halt
    call kprint

.hang:
    cli
    hlt
    jmp .hang

; ------------------------------------------------------------------------------
; Individual ISR Stubs
; ------------------------------------------------------------------------------
%macro ISR_NOERRCODE 2
isr%1:
    mov esi, %2
    jmp exception_common
%endmacro

ISR_NOERRCODE 0,  exc_msg_0
ISR_NOERRCODE 1,  exc_msg_1
ISR_NOERRCODE 2,  exc_msg_2
ISR_NOERRCODE 3,  exc_msg_3
ISR_NOERRCODE 4,  exc_msg_4
ISR_NOERRCODE 5,  exc_msg_5
ISR_NOERRCODE 6,  exc_msg_6
ISR_NOERRCODE 7,  exc_msg_7
ISR_NOERRCODE 8,  exc_msg_8
ISR_NOERRCODE 9,  exc_msg_9
ISR_NOERRCODE 10, exc_msg_10
ISR_NOERRCODE 11, exc_msg_11
ISR_NOERRCODE 12, exc_msg_12
ISR_NOERRCODE 13, exc_msg_13
ISR_NOERRCODE 14, exc_msg_14
ISR_NOERRCODE 16, exc_msg_16
ISR_NOERRCODE 17, exc_msg_17
ISR_NOERRCODE 18, exc_msg_18
ISR_NOERRCODE 19, exc_msg_19

isr_default:
    mov esi, exc_msg_unkn
    jmp exception_common
