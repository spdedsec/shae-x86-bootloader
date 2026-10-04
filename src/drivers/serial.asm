; ==============================================================================
; SHAE x86 Bootloader - 16550 UART Serial Driver (COM1)
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Port:         COM1 (I/O Port 0x03F8)
; Configuration:115200 Baud, 8 Data Bits, No Parity, 1 Stop Bit (8N1)
; Purpose:      Provides headless debugging output to QEMU stdio, hardware serial
;               consoles, and kernel telemetry.
; ==============================================================================

[BITS 32]

%include "include/serial.inc"

global serial_init
global serial_putchar
global serial_puts
global serial_put_hex32
global serial_put_hex16
global serial_put_hex8
global serial_put_dec
global serial_haschar
global serial_getchar
global kprint
global kprint_hex32
global kprint_dec

extern vga_putchar
extern vga_puts
extern vga_put_hex32
extern vga_put_dec

section .text

; ------------------------------------------------------------------------------
; Routine: serial_init
; Initializes COM1 UART to 115200 Baud, 8N1, FIFO enabled.
; ------------------------------------------------------------------------------
serial_init:
    push edx
    push eax

    ; 1. Disable all UART interrupts during configuration
    mov dx, COM1_BASE + UART_INT_ENABLE
    xor al, al
    out dx, al

    ; 2. Enable Divisor Latch Access Bit (DLAB) in Line Control Register
    mov dx, COM1_BASE + UART_LINE_CTRL
    mov al, 0x80                     ; Bit 7 = 1 (DLAB)
    out dx, al

    ; 3. Set baud rate divisor to 1 (115200 Baud)
    mov dx, COM1_BASE + UART_DIVISOR_LOW
    mov al, UART_BAUD_115200         ; Low byte = 1
    out dx, al

    mov dx, COM1_BASE + UART_DIVISOR_HIGH
    xor al, al                       ; High byte = 0
    out dx, al

    ; 4. Configure Line Control: 8 data bits, 1 stop bit, no parity (8N1), clear DLAB
    mov dx, COM1_BASE + UART_LINE_CTRL
    mov al, 0x03                     ; 8 bits, 1 stop bit, no parity
    out dx, al

    ; 5. Enable FIFO, clear transmit/receive queues, 14-byte threshold
    mov dx, COM1_BASE + UART_FIFO_CTRL
    mov al, 0xC7
    out dx, al

    ; 6. Configure Modem Control: RTS/DSR set, auxiliary output 2 enabled
    mov dx, COM1_BASE + UART_MODEM_CTRL
    mov al, 0x0B
    out dx, al

    pop eax
    pop edx
    ret

; ------------------------------------------------------------------------------
; Routine: serial_putchar
; Transmits a single character out of COM1.
; Handles line feed conversion (\n -> \r\n).
; Input: AL = ASCII character
; ------------------------------------------------------------------------------
serial_putchar:
    push edx
    push eax

    ; Convert newline '\n' to CR+LF for standard terminal consoles
    cmp al, 0x0A
    jne .wait_tx
    push eax
    mov al, 0x0D
    call .send_raw_byte
    pop eax

.wait_tx:
    call .send_raw_byte

    pop eax
    pop edx
    ret

.send_raw_byte:
    push eax
    mov dx, COM1_BASE + UART_LINE_STATUS
.poll_empty:
    in al, dx
    test al, UART_LSR_TX_EMPTY       ; Bit 5: Transmitter Holding Register Empty
    jz .poll_empty

    ; Write byte to Data Register
    pop eax
    mov dx, COM1_BASE + UART_DATA_REG
    out dx, al
    ret

; ------------------------------------------------------------------------------
; Routine: serial_puts
; Transmits a null-terminated ASCII string out of COM1.
; Input: ESI = pointer to string
; ------------------------------------------------------------------------------
serial_puts:
    push esi
    push eax
.loop:
    lodsb
    test al, al
    jz .done
    call serial_putchar
    jmp .loop
.done:
    pop eax
    pop esi
    ret

; ------------------------------------------------------------------------------
; Routine: serial_put_hex32
; Input: EAX = 32-bit value
; ------------------------------------------------------------------------------
serial_put_hex32:
    push eax
    push ecx
    push edx

    push eax
    mov al, '0'
    call serial_putchar
    mov al, 'x'
    call serial_putchar
    pop eax

    mov ecx, 8
.loop:
    rol eax, 4
    mov dl, al
    and dl, 0x0F
    cmp dl, 9
    jbe .digit
    add dl, 'A' - 10
    jmp .out
.digit:
    add dl, '0'
.out:
    push eax
    mov al, dl
    call serial_putchar
    pop eax
    loop .loop

    pop edx
    pop ecx
    pop eax
    ret

serial_put_hex16:
    push eax
    push ecx
    push edx
    push eax
    mov al, '0'
    call serial_putchar
    mov al, 'x'
    call serial_putchar
    pop eax
    mov ecx, 4
    rol ax, 4
.loop:
    mov dl, al
    and dl, 0x0F
    cmp dl, 9
    jbe .digit
    add dl, 'A' - 10
    jmp .out
.digit: add dl, '0'
.out:
    push eax
    mov al, dl
    call serial_putchar
    pop eax
    rol ax, 4
    loop .loop
    pop edx
    pop ecx
    pop eax
    ret

serial_put_hex8:
    push eax
    push edx
    mov dl, al
    shr dl, 4
    and dl, 0x0F
    cmp dl, 9
    jbe .d1
    add dl, 'A' - 10
    jmp .p1
.d1: add dl, '0'
.p1:
    push eax
    mov al, dl
    call serial_putchar
    pop eax
    mov dl, al
    and dl, 0x0F
    cmp dl, 9
    jbe .d2
    add dl, 'A' - 10
    jmp .p2
.d2: add dl, '0'
.p2:
    push eax
    mov al, dl
    call serial_putchar
    pop eax
    pop edx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: serial_put_dec
; Input: EAX = 32-bit unsigned integer
; ------------------------------------------------------------------------------
serial_put_dec:
    push eax
    push ebx
    push ecx
    push edx

    test eax, eax
    jnz .nonzero
    mov al, '0'
    call serial_putchar
    jmp .done

.nonzero:
    xor ecx, ecx
    mov ebx, 10
.div_loop:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .div_loop

.print_loop:
    pop edx
    add dl, '0'
    mov al, dl
    call serial_putchar
    loop .print_loop

.done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: serial_haschar
; Checks if a character is available in the receiver FIFO.
; Returns: AL = 1 if character ready, AL = 0 if none
; ------------------------------------------------------------------------------
serial_haschar:
    push edx
    mov dx, COM1_BASE + UART_LINE_STATUS
    in al, dx
    and al, UART_LSR_DATA_READY
    pop edx
    ret

; ------------------------------------------------------------------------------
; Routine: serial_getchar
; Waits for and retrieves a byte from the serial port.
; Returns: AL = received byte
; ------------------------------------------------------------------------------
serial_getchar:
    push edx
    mov dx, COM1_BASE + UART_LINE_STATUS
.wait:
    in al, dx
    test al, UART_LSR_DATA_READY
    jz .wait
    mov dx, COM1_BASE + UART_DATA_REG
    in al, dx
    pop edx
    ret

; ------------------------------------------------------------------------------
; DUAL OUTPUT HELPERS (Mirror output to both VGA Display and Serial COM1)
; ------------------------------------------------------------------------------
kprint:
    push esi
    call vga_puts
    call serial_puts
    pop esi
    ret

kprint_char:
    push eax
    call vga_putchar
    call serial_putchar
    pop eax
    ret

kprint_hex8:
    push eax
    call vga_put_hex8
    call serial_put_hex8
    pop eax
    ret

kprint_hex32:
    push eax
    call vga_put_hex32
    call serial_put_hex32
    pop eax
    ret

kprint_dec:
    push eax
    call vga_put_dec
    call serial_put_dec
    pop eax
    ret
