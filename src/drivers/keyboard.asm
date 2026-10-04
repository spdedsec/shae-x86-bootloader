; ==============================================================================
; SHAE x86 Bootloader - PS/2 Keyboard & Unified Input Driver
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Ports:        PS/2 Data Port: 0x60, PS/2 Status Port: 0x64, COM1 Serial: 0x3F8
; Purpose:      Translates PS/2 Scancode Set 1 into ASCII characters and merges
;               keyboard input with Serial COM1 input for dual interactive operation.
; ==============================================================================

[BITS 32]

global keyboard_init
global keyboard_haschar
global keyboard_getchar
global keyboard_readline

extern serial_haschar
extern serial_getchar
extern serial_putchar
extern vga_putchar

section .data
shift_active:   db 0

; Scancode Set 1 to ASCII Table (Unshifted)
scancode_table:
    db 0,  27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8, 9
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 10, 0
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0, '\'
    db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' '
    times 128 db 0

; Scancode Set 1 to ASCII Table (Shifted)
scancode_shift_table:
    db 0,  27, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 8, 9
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 10, 0
    db 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0, '|'
    db 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' '
    times 128 db 0

section .text

; ------------------------------------------------------------------------------
; Routine: keyboard_init
; Clears keyboard buffer and state.
; ------------------------------------------------------------------------------
keyboard_init:
    mov byte [shift_active], 0
    ; Flush any residual bytes in the controller
.flush:
    in al, 0x64
    test al, 1
    jz .done
    in al, 0x60
    jmp .flush
.done:
    ret

; ------------------------------------------------------------------------------
; Routine: keyboard_haschar
; Checks if an input character is pending from either PS/2 keyboard or Serial.
; Returns: AL = 1 if character ready, AL = 0 if none
; ------------------------------------------------------------------------------
keyboard_haschar:
    ; 1. Check Serial Port COM1 first
    call serial_haschar
    test al, al
    jnz .ready

    ; 2. Check PS/2 Status Register (Port 0x64)
    in al, 0x64
    and al, 1                        ; Bit 0: Output buffer full
    ret

.ready:
    mov al, 1
    ret

; ------------------------------------------------------------------------------
; Routine: keyboard_getchar
; Blocking read of next input character from Serial or PS/2 Keyboard.
; Returns: AL = ASCII character
; ------------------------------------------------------------------------------
keyboard_getchar:
    push ebx

.poll_loop:
    ; Check serial port input
    call serial_haschar
    test al, al
    jz .check_ps2
    call serial_getchar
    ; Translate carriage return (0x0D) to newline (0x0A)
    cmp al, 0x0D
    jne .return_char
    mov al, 0x0A
    jmp .return_char

.check_ps2:
    in al, 0x64
    test al, 1
    jz .poll_loop

    ; Read PS/2 scan code
    in al, 0x60

    ; Handle Shift press (Left Shift = 0x2A, Right Shift = 0x36)
    cmp al, 0x2A
    je .shift_down
    cmp al, 0x36
    je .shift_down

    ; Handle Shift release (0xAA, 0xB6)
    cmp al, 0xAA
    je .shift_up
    cmp al, 0xB6
    je .shift_up

    ; Check if this is a key release (Break code, high bit set)
    test al, 0x80
    jnz .poll_loop

    ; Convert make scancode to ASCII
    movzx ebx, al
    cmp byte [shift_active], 1
    je .use_shift_table

    mov al, [scancode_table + ebx]
    jmp .test_valid

.use_shift_table:
    mov al, [scancode_shift_table + ebx]

.test_valid:
    test al, al
    jz .poll_loop                    ; Unknown or non-printable key -> continue polling

.return_char:
    pop ebx
    ret

.shift_down:
    mov byte [shift_active], 1
    jmp .poll_loop

.shift_up:
    mov byte [shift_active], 0
    jmp .poll_loop

; ------------------------------------------------------------------------------
; Routine: keyboard_readline
; Reads a full line of text into a buffer with backspace editing and echo.
; Input:  EDI = pointer to destination string buffer
;         ECX = maximum buffer size (including null terminator)
; Returns: EAX = number of characters read
; ------------------------------------------------------------------------------
keyboard_readline:
    push ebx
    push edx
    push edi

    xor edx, edx                     ; EDX = characters currently stored
    dec ecx                          ; Reserve 1 byte for null terminator

.read_char:
    call keyboard_getchar

    ; Check for Enter (0x0A = newline)
    cmp al, 0x0A
    je .handle_enter

    ; Check for Backspace (0x08)
    cmp al, 0x08
    je .handle_backspace
    cmp al, 0x7F                     ; Delete key / backspace in some terminals
    je .handle_backspace

    ; Ignore control chars below 0x20 except tab
    cmp al, 0x20
    jb .read_char

    ; Check buffer capacity
    cmp edx, ecx
    jge .read_char                   ; Buffer full -> ignore extra chars

    ; Store character in buffer
    mov [edi + edx], al
    inc edx

    ; Echo character to VGA screen and Serial
    push eax
    call vga_putchar
    pop eax
    call serial_putchar

    jmp .read_char

.handle_backspace:
    test edx, edx
    jz .read_char                    ; Nothing to backspace

    dec edx

    ; Erase on screen
    mov al, 0x08
    call vga_putchar
    ; Erase on serial terminal (backspace, space, backspace)
    mov al, 0x08
    call serial_putchar
    mov al, ' '
    call serial_putchar
    mov al, 0x08
    call serial_putchar

    jmp .read_char

.handle_enter:
    ; Null-terminate string
    mov byte [edi + edx], 0

    ; Print newline to both outputs
    mov al, 0x0A
    call vga_putchar
    call serial_putchar

    mov eax, edx                     ; Return length in EAX
    pop edi
    pop edx
    pop ebx
    ret
