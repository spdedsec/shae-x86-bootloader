; ==============================================================================
; SHAE x86 Bootloader - Interactive 32-bit Protected Mode Shell
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Purpose:      Interactive diagnostic command-line interface providing hardware
;               telemetry, memory inspection, CPU analysis, and kernel execution.
; ==============================================================================

[BITS 32]

%include "include/boot.inc"
%include "include/vga.inc"

global shell_main

extern vga_init
extern vga_clear
extern vga_putchar
extern vga_puts
extern vga_puts_color
extern vga_set_color
extern vga_put_hex32
extern vga_put_dec
extern kprint
extern kprint_hex32
extern kprint_dec
extern keyboard_readline
extern cpu_print_info
extern mmap_print_table
extern mmap_get_total_usable_kb

section .data
align 4

banner:
    db "================================================================================", 13, 10
    db "  ____  _   _    _    _____            ___   ___   _    ", 13, 10
    db " / ___|| | | |  / \  | ____|          / _ \ / _ \ / |   ", 13, 10
    db " \___ \| |_| | / _ \ |  _|   ______  | (_) | | | || |   ", 13, 10
    db "  ___) |  _  |/ ___ \| |___ |______|  \__, | |_| || |   ", 13, 10
    db " |____/|_| |_/_/   \_\_____|            /_/ \___/ |_|   ", 13, 10
    db "        SHAE Multistage x86 Protected Mode Bootloader (v1.0)                     ", 13, 10
    db "================================================================================", 13, 10, 0

system_status_line:
    db "[STATUS] Mode: 32-bit Protected | A20: Active | GDT: Flat 4GB | IDT: Loaded", 13, 10, 0
help_hint:
    db "Type 'help' to view available diagnostic commands.", 13, 10, 13, 10, 0

prompt_str:         db "shae> ", 0
cmd_unknown:        db "Unknown command: '", 0
cmd_unknown_end:    db "'. Type 'help' for command list.", 13, 10, 0

; Command Strings
cmd_help_str:       db "help", 0
cmd_cpu_str:        db "cpuinfo", 0
cmd_mmap_str:       db "mmap", 0
cmd_vga_str:        db "vga", 0
cmd_dump_str:       db "dump", 0
cmd_clear_str:      db "clear", 0
cmd_reboot_str:     db "reboot", 0
cmd_halt_str:       db "halt", 0
cmd_kernel_str:     db "kernel", 0
cmd_about_str:      db "about", 0

msg_help:
    db 13, 10
    db "Available Shell Commands:", 13, 10
    db "  help       - Display this list of commands", 13, 10
    db "  cpuinfo    - Inspect CPUID vendor, brand model, and feature flags", 13, 10
    db "  mmap       - Dump BIOS E820 physical memory regions & usable RAM", 13, 10
    db "  vga        - Display 16-color VGA text palette matrix", 13, 10
    db "  dump       - Hexadecimal memory dump of MBR boot sector at 0x7C00", 13, 10
    db "  clear      - Clear the display screen", 13, 10
    db "  about      - Display SHAE Bootloader architectural information", 13, 10
    db "  kernel     - Execute secondary OS Kernel payload loaded at 0x100000", 13, 10
    db "  reboot     - Restart computer via 8042 keyboard controller reset", 13, 10
    db "  halt       - Halt CPU execution (cli; hlt)", 13, 10, 13, 10, 0

msg_about:
    db 13, 10
    db "================== [ABOUT SHAE X86 BOOTLOADER] ==================", 13, 10
    db " Author:      spdedsec", 13, 10
    db " Target:      IBM PC / x86 Architecture (IA-32)", 13, 10
    db " Pipeline:    BIOS POST -> Stage 1 MBR (0x7C00) -> Stage 2 (0x8000)", 13, 10
    db "              -> A20 Enabled -> E820 Map -> 32-bit Protected Mode", 13, 10
    db "              -> GDT (Flat 4GB) -> 8259A PIC Remap -> 256-gate IDT", 13, 10
    db "              -> VGA 80x25 Driver -> 16550 UART Serial Driver (COM1)", 13, 10
    db "              -> PS/2 Keyboard Driver -> Interactive Shell", 13, 10
    db "=================================================================", 13, 10, 13, 10, 0

msg_rebooting:      db "Rebooting machine...", 13, 10, 0
msg_halting:        db "Halting CPU...", 13, 10, 0
msg_launching_kern: db "Transferring execution to Kernel at 0x100000...", 13, 10, 0
msg_no_kern:        db "[!] No executable kernel found at 0x100000 (empty payload).", 13, 10, 0

str_dump_header:
    db 13, 10, "=== [HEX DUMP: MBR Boot Sector at 0x00007C00] ===", 13, 10, 0

section .bss
align 4
input_buffer:       resb 128

section .text

; ------------------------------------------------------------------------------
; Routine: shell_main
; Main entry point and Read-Eval-Print Loop (REPL) for the SHAE shell.
; ------------------------------------------------------------------------------
shell_main:
    ; Print welcome banner in bright cyan
    mov al, COLOR_CYAN_ON_BLACK
    call vga_set_color
    mov esi, banner
    call kprint

    ; Print status line in light green
    mov al, COLOR_GREEN_ON_BLACK
    call vga_set_color
    mov esi, system_status_line
    call kprint

    ; Print hint in white
    mov al, COLOR_WHITE_ON_BLACK
    call vga_set_color
    mov esi, help_hint
    call kprint

.repl_loop:
    ; Display prompt in bright yellow
    mov al, 0x0E
    call vga_set_color
    mov esi, prompt_str
    call kprint

    ; Reset text color to white for user typing
    mov al, COLOR_WHITE_ON_BLACK
    call vga_set_color

    ; Read command string from keyboard/serial
    mov edi, input_buffer
    mov ecx, 128
    call keyboard_readline

    ; Skip empty lines
    cmp byte [input_buffer], 0
    je .repl_loop

    ; --------------------------------------------------------------------------
    ; Command Dispatcher
    ; --------------------------------------------------------------------------
    mov esi, input_buffer
    mov edi, cmd_help_str
    call strcmp
    jz .do_help

    mov esi, input_buffer
    mov edi, cmd_cpu_str
    call strcmp
    jz .do_cpuinfo

    mov esi, input_buffer
    mov edi, cmd_mmap_str
    call strcmp
    jz .do_mmap

    mov esi, input_buffer
    mov edi, cmd_vga_str
    call strcmp
    jz .do_vga

    mov esi, input_buffer
    mov edi, cmd_dump_str
    call strcmp
    jz .do_dump

    mov esi, input_buffer
    mov edi, cmd_clear_str
    call strcmp
    jz .do_clear

    mov esi, input_buffer
    mov edi, cmd_about_str
    call strcmp
    jz .do_about

    mov esi, input_buffer
    mov edi, cmd_reboot_str
    call strcmp
    jz .do_reboot

    mov esi, input_buffer
    mov edi, cmd_halt_str
    call strcmp
    jz .do_halt

    mov esi, input_buffer
    mov edi, cmd_kernel_str
    call strcmp
    jz .do_kernel

    ; Unknown command
    mov esi, cmd_unknown
    call kprint
    mov esi, input_buffer
    call kprint
    mov esi, cmd_unknown_end
    call kprint
    jmp .repl_loop

.do_help:
    mov esi, msg_help
    call kprint
    jmp .repl_loop

.do_cpuinfo:
    call cpu_print_info
    jmp .repl_loop

.do_mmap:
    call mmap_print_table
    jmp .repl_loop

.do_vga:
    call do_vga_palette_demo
    jmp .repl_loop

.do_dump:
    call do_memory_dump
    jmp .repl_loop

.do_clear:
    call vga_clear
    jmp .repl_loop

.do_about:
    mov esi, msg_about
    call kprint
    jmp .repl_loop

.do_reboot:
    mov esi, msg_rebooting
    call kprint
    ; 8042 Keyboard Controller Reset command (Port 0x64, Command 0xFE)
.wait_kbc:
    in al, 0x64
    test al, 2
    jnz .wait_kbc
    mov al, 0xFE
    out 0x64, al
    ; Fallback: Triple fault
    lidt [gdt_start]                 ; Load bogus IDT
    int 3                            ; Trigger CPU exception -> triple fault reset
    jmp .repl_loop

.do_halt:
    mov esi, msg_halting
    call kprint
    cli
    hlt
    jmp .repl_loop

.do_kernel:
    ; Verify kernel payload exists (first dword != 0)
    mov eax, [KERNEL_LOAD_ADDR]
    test eax, eax
    jz .no_kernel_found
    cmp eax, 0xFFFFFFFF
    je .no_kernel_found

    mov esi, msg_launching_kern
    call kprint
    ; Pass E820 memory map count in EAX to kernel
    movzx eax, word [MMAP_COUNT_ADDR]
    mov ebx, MMAP_ENTRIES_ADDR
    call KERNEL_LOAD_ADDR
    jmp .repl_loop

.no_kernel_found:
    mov esi, msg_no_kern
    call kprint
    jmp .repl_loop

; ------------------------------------------------------------------------------
; Routine: do_vga_palette_demo
; Prints all 16 VGA colors in a formatted grid.
; ------------------------------------------------------------------------------
do_vga_palette_demo:
    pusha
    mov esi, str_vga_demo_title
    call kprint

    xor ecx, ecx                     ; Color index 0..15
.color_loop:
    mov al, cl
    call vga_set_color
    mov esi, str_color_block
    call kprint

    inc ecx
    cmp ecx, 16
    jl .color_loop

    mov al, COLOR_WHITE_ON_BLACK
    call vga_set_color
    mov esi, str_shell_nl
    call kprint
    popa
    ret

; ------------------------------------------------------------------------------
; Routine: do_memory_dump
; Dumps 64 bytes of memory from 0x7C00 (MBR) in formatted hex.
; ------------------------------------------------------------------------------
do_memory_dump:
    pusha
    mov esi, str_dump_header
    call kprint

    mov esi, 0x7C00                  ; Start at MBR address
    mov ecx, 4                       ; 4 lines of 16 bytes = 64 bytes

.line_loop:
    push ecx
    ; Print memory address
    mov eax, esi
    call kprint_hex32
    mov al, ':'
    call kprint_char
    mov al, ' '
    call kprint_char

    ; Print 16 bytes in hex
    push esi
    mov ecx, 16
.byte_loop:
    lodsb
    call kprint_hex8_space
    loop .byte_loop
    pop esi

    ; Print ASCII representation
    mov al, '|'
    call kprint_char
    mov ecx, 16
.ascii_loop:
    lodsb
    cmp al, 32
    jb .dot
    cmp al, 126
    ja .dot
    call kprint_char
    jmp .next_ascii
.dot:
    mov al, '.'
    call kprint_char
.next_ascii:
    loop .ascii_loop
    mov al, '|'
    call kprint_char

    mov al, 10
    call kprint_char

    pop ecx
    loop .line_loop

    popa
    ret

kprint_hex8_space:
    push eax
    call kprint_hex8
    mov al, ' '
    call kprint_char
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: strcmp
; Compares null-terminated strings at ESI and EDI.
; Returns: ZF=1 if equal, ZF=0 if different
; ------------------------------------------------------------------------------
strcmp:
    push esi
    push edi
    push eax
.compare_char:
    mov al, [esi]
    cmp al, [edi]
    jne .not_equal
    test al, al
    jz .equal
    inc esi
    inc edi
    jmp .compare_char
.not_equal:
    pop eax
    pop edi
    pop esi
    test esp, esp                    ; Clear ZF
    ret
.equal:
    pop eax
    pop edi
    pop esi
    xor eax, eax                     ; Set ZF
    ret

section .data
str_vga_demo_title: db 13, 10, "VGA 16-Color Palette Matrix:", 13, 10, 0
str_color_block:    db " [COLOR] ", 0
str_shell_nl:       db 13, 10, 0
