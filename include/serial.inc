; ==============================================================================
; SHAE x86 Bootloader - 16550 UART Serial Port Definitions
; ==============================================================================

%ifndef SERIAL_INC
%define SERIAL_INC

; Standard COM Port Base I/O Addresses
COM1_BASE           equ 0x03F8
COM2_BASE           equ 0x02F8

; Register Offsets from Base
UART_DATA_REG       equ 0           ; Receiver / Transmitter buffer (DLAB=0)
UART_DIVISOR_LOW    equ 0           ; Divisor Latch Low (DLAB=1)
UART_INT_ENABLE     equ 1           ; Interrupt Enable Register (DLAB=0)
UART_DIVISOR_HIGH   equ 1           ; Divisor Latch High (DLAB=1)
UART_FIFO_CTRL      equ 2           ; FIFO Control Register (write)
UART_LINE_CTRL      equ 3           ; Line Control Register
UART_MODEM_CTRL     equ 4           ; Modem Control Register
UART_LINE_STATUS    equ 5           ; Line Status Register
UART_MODEM_STATUS   equ 6           ; Modem Status Register
UART_SCRATCH        equ 7           ; Scratch Register

; Line Status Register Bits
UART_LSR_DATA_READY equ 0x01        ; Bit 0: Data Ready in receiver
UART_LSR_TX_EMPTY   equ 0x20        ; Bit 5: Transmitter Holding Register Empty

; Baud Rate Divisors (115200 base clock)
UART_BAUD_115200    equ 1           ; 115200 / 1
UART_BAUD_57600     equ 2           ; 115200 / 2
UART_BAUD_38400     equ 3           ; 115200 / 3
UART_BAUD_9600      equ 12          ; 115200 / 12

%endif ; SERIAL_INC
