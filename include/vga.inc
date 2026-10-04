; ==============================================================================
; SHAE x86 Bootloader - VGA Text Mode 80x25 Definitions
; ==============================================================================

%ifndef VGA_INC
%define VGA_INC

; VGA Physical Memory
VGA_VIDEO_MEMORY    equ 0x000B8000  ; Base address of color text buffer
VGA_COLS            equ 80          ; 80 columns wide
VGA_ROWS            equ 25          ; 25 rows tall
VGA_TOTAL_CELLS     equ 2000        ; 80 * 25
VGA_BUFFER_SIZE     equ 4000        ; 2000 cells * 2 bytes (char + attr)

; VGA CRT Controller Ports (Cursor control)
VGA_CRTC_INDEX_PORT equ 0x03D4      ; Index register
VGA_CRTC_DATA_PORT  equ 0x03D5      ; Data register
VGA_CURSOR_HIGH_REG equ 0x0E        ; Cursor location high byte index
VGA_CURSOR_LOW_REG  equ 0x0F        ; Cursor location low byte index

; Standard 16-Color Palette Codes
VGA_BLACK           equ 0x00
VGA_BLUE            equ 0x01
VGA_GREEN           equ 0x02
VGA_CYAN            equ 0x03
VGA_RED             equ 0x04
VGA_MAGENTA         equ 0x05
VGA_BROWN           equ 0x06
VGA_LIGHT_GRAY      equ 0x07
VGA_DARK_GRAY       equ 0x08
VGA_LIGHT_BLUE      equ 0x09
VGA_LIGHT_GREEN     equ 0x0A
VGA_LIGHT_CYAN      equ 0x0B
VGA_LIGHT_RED       equ 0x0C
VGA_LIGHT_MAGENTA   equ 0x0D
VGA_YELLOW          equ 0x0E
VGA_WHITE           equ 0x0F

; Common Default Color Attributes (Foreground | (Background << 4))
COLOR_WHITE_ON_BLACK equ 0x0F
COLOR_CYAN_ON_BLACK  equ 0x0B
COLOR_GREEN_ON_BLACK equ 0x0A
COLOR_RED_ON_BLACK   equ 0x0C
COLOR_YELLOW_ON_BLUE equ 0x1E
COLOR_BLACK_ON_GRAY  equ 0x70

%endif ; VGA_INC
