; ==============================================================================
; SHAE x86 Bootloader - VGA Text Mode 80x25 Driver
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Video RAM:    0x000B8000
; Resolution:   80 columns x 25 rows (2000 cells, 4000 bytes)
; Cell Format:  Byte 0 = ASCII character, Byte 1 = Color Attribute byte
; Attribute:    [Bits 7:4 Background Color (0-7)] | [Bits 3:0 Foreground Color (0-15)]
; ==============================================================================

[BITS 32]

%include "include/vga.inc"

global vga_init
global vga_clear
global vga_putchar
global vga_puts
global vga_puts_color
global vga_put_hex32
global vga_put_hex16
global vga_put_hex8
global vga_put_dec
global vga_set_cursor
global vga_set_color
global vga_get_color
global vga_cursor_row
global vga_cursor_col
global vga_current_color

section .data
vga_cursor_row:     dd 0
vga_cursor_col:     dd 0
vga_current_color:  db COLOR_WHITE_ON_BLACK

section .text

; ------------------------------------------------------------------------------
; Routine: vga_init
; Initializes VGA text driver, clears the screen, and positions hardware cursor.
; ------------------------------------------------------------------------------
vga_init:
    push eax
    mov byte [vga_current_color], COLOR_WHITE_ON_BLACK
    call vga_clear
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: vga_set_color
; Sets the active color attribute byte for subsequent characters.
; Input: AL = color attribute byte
; ------------------------------------------------------------------------------
vga_set_color:
    mov [vga_current_color], al
    ret

vga_get_color:
    mov al, [vga_current_color]
    ret

; ------------------------------------------------------------------------------
; Routine: vga_clear
; Clears all 2000 VGA cells with space (0x20) and resets the cursor to (0,0).
; ------------------------------------------------------------------------------
vga_clear:
    push eax
    push ecx
    push edi

    mov edi, VGA_VIDEO_MEMORY
    mov ah, [vga_current_color]       ; Color attribute
    mov al, ' '                      ; ASCII space
    mov ecx, VGA_TOTAL_CELLS

    rep stosw                        ; Write AX to [EDI] ECX times (4000 bytes)

    mov dword [vga_cursor_row], 0
    mov dword [vga_cursor_col], 0
    call vga_update_hw_cursor

    pop edi
    pop ecx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: vga_putchar
; Emits a single character to the screen, handling control characters and scrolling.
; Input: AL = ASCII character
; ------------------------------------------------------------------------------
vga_putchar:
    push eax
    push ebx
    push edx
    push edi

    ; Handle newline (\n = 0x0A)
    cmp al, 0x0A
    je .handle_newline

    ; Handle carriage return (\r = 0x0D)
    cmp al, 0x0D
    je .handle_cr

    ; Handle backspace (\b = 0x08)
    cmp al, 0x08
    je .handle_backspace

    ; Handle tab (\t = 0x09)
    cmp al, 0x09
    je .handle_tab

    ; Ordinary printable character
    ; Compute video offset: (row * 80 + col) * 2
    mov edx, [vga_cursor_row]
    imul edx, VGA_COLS
    add edx, [vga_cursor_col]
    shl edx, 1                       ; Multiply by 2 (2 bytes per cell)

    mov edi, VGA_VIDEO_MEMORY
    add edi, edx

    mov ah, [vga_current_color]
    mov [edi], ax                    ; Store char (AL) and attribute (AH)

    ; Advance column
    inc dword [vga_cursor_col]
    cmp dword [vga_cursor_col], VGA_COLS
    jl .done_char

    ; Wrap to next line
    mov dword [vga_cursor_col], 0
    inc dword [vga_cursor_row]
    jmp .check_scroll

.handle_newline:
    mov dword [vga_cursor_col], 0
    inc dword [vga_cursor_row]
    jmp .check_scroll

.handle_cr:
    mov dword [vga_cursor_col], 0
    jmp .done_char

.handle_backspace:
    cmp dword [vga_cursor_col], 0
    je .done_char
    dec dword [vga_cursor_col]
    ; Clear character at cursor
    mov edx, [vga_cursor_row]
    imul edx, VGA_COLS
    add edx, [vga_cursor_col]
    shl edx, 1
    mov edi, VGA_VIDEO_MEMORY
    add edi, edx
    mov byte [edi], ' '
    jmp .done_char

.handle_tab:
    ; Advance cursor to next multiple of 4 columns
    mov edx, [vga_cursor_col]
    add edx, 4
    and edx, ~3                      ; Align to 4
    cmp edx, VGA_COLS
    jl .tab_fit
    mov edx, 0
    inc dword [vga_cursor_row]
.tab_fit:
    mov [vga_cursor_col], edx
    jmp .check_scroll

.check_scroll:
    cmp dword [vga_cursor_row], VGA_ROWS
    jl .done_char
    call vga_scroll_up

.done_char:
    call vga_update_hw_cursor
    pop edi
    pop edx
    pop ebx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: vga_scroll_up
; Shifts the entire display up by one row when text exceeds row 24.
; ------------------------------------------------------------------------------
vga_scroll_up:
    push esi
    push edi
    push ecx
    push eax

    ; Destination: row 0 (0xB8000)
    mov edi, VGA_VIDEO_MEMORY
    ; Source: row 1 (0xB8000 + 80 * 2)
    mov esi, VGA_VIDEO_MEMORY + (VGA_COLS * 2)
    ; Move 24 rows = 24 * 80 cells = 1920 cells = 960 dwords
    mov ecx, ((VGA_ROWS - 1) * VGA_COLS * 2) / 4
    rep movsd

    ; Clear the last row (row 24)
    mov edi, VGA_VIDEO_MEMORY + ((VGA_ROWS - 1) * VGA_COLS * 2)
    mov ah, [vga_current_color]
    mov al, ' '
    mov ecx, VGA_COLS
    rep stosw

    mov dword [vga_cursor_row], VGA_ROWS - 1
    mov dword [vga_cursor_col], 0

    pop eax
    pop ecx
    pop edi
    pop esi
    ret

; ------------------------------------------------------------------------------
; Routine: vga_update_hw_cursor
; Repositions the blinking VGA hardware cursor to (vga_cursor_row, vga_cursor_col).
; ------------------------------------------------------------------------------
vga_update_hw_cursor:
    push eax
    push edx

    mov eax, [vga_cursor_row]
    imul eax, VGA_COLS
    add eax, [vga_cursor_col]

    ; Low cursor byte -> register 0x0F
    mov edx, VGA_CRTC_INDEX_PORT
    mov al, VGA_CURSOR_LOW_REG
    out dx, al

    mov edx, VGA_CRTC_DATA_PORT
    mov eax, [vga_cursor_row]
    imul eax, VGA_COLS
    add eax, [vga_cursor_col]
    out dx, al

    ; High cursor byte -> register 0x0E
    mov edx, VGA_CRTC_INDEX_PORT
    mov al, VGA_CURSOR_HIGH_REG
    out dx, al

    mov edx, VGA_CRTC_DATA_PORT
    mov eax, [vga_cursor_row]
    imul eax, VGA_COLS
    add eax, [vga_cursor_col]
    shr eax, 8
    out dx, al

    pop edx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: vga_set_cursor
; Explicitly moves the cursor to a specific row and column.
; Input: EAX = row (0..24), EBX = col (0..79)
; ------------------------------------------------------------------------------
vga_set_cursor:
    mov [vga_cursor_row], eax
    mov [vga_cursor_col], ebx
    call vga_update_hw_cursor
    ret

; ------------------------------------------------------------------------------
; Routine: vga_puts
; Prints a null-terminated ASCII string using the current color attribute.
; Input: ESI = pointer to string
; ------------------------------------------------------------------------------
vga_puts:
    push eax
    push esi
.loop:
    lodsb
    test al, al
    jz .done
    call vga_putchar
    jmp .loop
.done:
    pop esi
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: vga_puts_color
; Prints a null-terminated ASCII string with a temporary color attribute.
; Input: ESI = pointer to string, AL = color attribute byte
; ------------------------------------------------------------------------------
vga_puts_color:
    push ebx
    mov bl, [vga_current_color]      ; Save old color
    mov [vga_current_color], al      ; Apply temporary color
    call vga_puts
    mov [vga_current_color], bl      ; Restore old color
    pop ebx
    ret

; ------------------------------------------------------------------------------
; Routine: vga_put_hex32
; Formats and prints a 32-bit unsigned integer in hexadecimal format (e.g. 0x12AB34CD).
; Input: EAX = 32-bit integer
; ------------------------------------------------------------------------------
vga_put_hex32:
    push eax
    push ecx
    push edx

    push eax
    mov al, '0'
    call vga_putchar
    mov al, 'x'
    call vga_putchar
    pop eax

    mov ecx, 8                       ; 8 hex nibbles in 32-bit integer
.nibble_loop:
    rol eax, 4                       ; Rotate highest nibble into low 4 bits
    mov dl, al
    and dl, 0x0F
    cmp dl, 9
    jbe .is_digit
    add dl, 'A' - 10
    jmp .print_nibble
.is_digit:
    add dl, '0'
.print_nibble:
    push eax
    mov al, dl
    call vga_putchar
    pop eax
    loop .nibble_loop

    pop edx
    pop ecx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: vga_put_hex16
; Input: AX = 16-bit integer
; ------------------------------------------------------------------------------
vga_put_hex16:
    push eax
    push ecx
    push edx

    push eax
    mov al, '0'
    call vga_putchar
    mov al, 'x'
    call vga_putchar
    pop eax

    mov ecx, 4
    rol ax, 4
.loop:
    mov dl, al
    and dl, 0x0F
    cmp dl, 9
    jbe .is_digit
    add dl, 'A' - 10
    jmp .print_nibble
.is_digit:
    add dl, '0'
.print_nibble:
    push eax
    mov al, dl
    call vga_putchar
    pop eax
    rol ax, 4
    loop .loop

    pop edx
    pop ecx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: vga_put_hex8
; Input: AL = 8-bit integer
; ------------------------------------------------------------------------------
vga_put_hex8:
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
    call vga_putchar
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
    call vga_putchar
    pop eax

    pop edx
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: vga_put_dec
; Formats and prints a 32-bit unsigned integer in base 10.
; Input: EAX = 32-bit integer
; ------------------------------------------------------------------------------
vga_put_dec:
    push eax
    push ebx
    push ecx
    push edx

    test eax, eax
    jnz .nonzero
    mov al, '0'
    call vga_putchar
    jmp .done

.nonzero:
    xor ecx, ecx                     ; Digit count
    mov ebx, 10                      ; Divisor

.div_loop:
    xor edx, edx
    div ebx                          ; EAX / 10 -> quotient in EAX, remainder in EDX
    push edx                         ; Push remainder (0..9) onto stack
    inc ecx
    test eax, eax
    jnz .div_loop

.print_loop:
    pop edx
    add dl, '0'
    mov al, dl
    call vga_putchar
    loop .print_loop

.done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret
