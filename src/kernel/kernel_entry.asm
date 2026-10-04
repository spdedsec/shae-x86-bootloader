; ==============================================================================
; SHAE x86 Bootloader - 32-bit Protected Mode Kernel Subsystem Initializer
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Purpose:      Initializes serial port, VGA console, PIC 8259A, IDT gates,
;               and keyboard driver, then launches the interactive shell.
; ==============================================================================

[BITS 32]

global kernel_main

extern vga_init
extern serial_init
extern pic_remap
extern idt_init
extern keyboard_init
extern shell_main
extern kprint

section .data
msg_boot_init:
    db "[INIT] Initializing 32-bit Protected Mode Hardware Subsystems...", 13, 10, 0
msg_vga_ok:
    db "  [OK] VGA 80x25 Console Buffer (0xB8000)", 13, 10, 0
msg_serial_ok:
    db "  [OK] 16550 UART Serial Port (COM1 115200 8N1)", 13, 10, 0
msg_pic_ok:
    db "  [OK] 8259A Dual PIC Remapped (Vectors 0x20..0x2F)", 13, 10, 0
msg_idt_ok:
    db "  [OK] Interrupt Descriptor Table (256 Gates & Exception Handlers)", 13, 10, 0
msg_kbd_ok:
    db "  [OK] PS/2 Keyboard Driver & Serial Input Multiplexer", 13, 10, 0
msg_shell_launch:
    db "[INIT] Launching SHAE Interactive Diagnostic Console...", 13, 10, 13, 10, 0

section .text

; ------------------------------------------------------------------------------
; Routine: kernel_main
; Called directly by Stage 2 upon entering 32-bit Protected Mode.
; ------------------------------------------------------------------------------
kernel_main:
    ; 1. Initialize Serial Port COM1 first (enables immediate debug logging)
    call serial_init

    ; 2. Initialize VGA Text Mode Display
    call vga_init

    ; 3. Remap 8259A PIC (to prevent hardware IRQs colliding with CPU exceptions)
    call pic_remap

    ; 4. Install 256-gate IDT and CPU Exception handlers (prevents triple faults)
    call idt_init

    ; 5. Initialize PS/2 Keyboard controller and translation tables
    call keyboard_init

    ; Log initialization progress
    mov esi, msg_boot_init
    call kprint
    mov esi, msg_vga_ok
    call kprint
    mov esi, msg_serial_ok
    call kprint
    mov esi, msg_pic_ok
    call kprint
    mov esi, msg_idt_ok
    call kprint
    mov esi, msg_kbd_ok
    call kprint
    mov esi, msg_shell_launch
    call kprint

    ; 6. Launch the interactive diagnostic shell
    call shell_main

    ; If shell terminates, halt the system
.system_halt:
    cli
    hlt
    jmp .system_halt
