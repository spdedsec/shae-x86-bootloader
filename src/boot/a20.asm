; ==============================================================================
; SHAE x86 Bootloader - A20 Gate Controller & Detection
; ==============================================================================
; Architecture: x86 (16-bit Real Mode)
; Purpose:      Verify and enable the Address Line 20 (A20) gate.
; Background:   The IBM PC AT (80286) introduced the A20 gate to maintain
;               bug-for-bug compatibility with the 8086 1MB memory wrap-around.
;               To access memory above 1MB in Protected Mode, A20 must be enabled.
; ==============================================================================

[BITS 16]

; ------------------------------------------------------------------------------
; Routine: enable_a20
; Attempts to enable the A20 gate using multiple redundant fallbacks:
; 1. Verification if already enabled by BIOS/firmware
; 2. BIOS INT 15h, AX=2401h
; 3. Fast A20 Gate (System Control Port A: I/O port 0x92)
; 4. Keyboard Controller (8042 MCU output port manipulation)
; Returns: AX = 0 on success, AX = 1 on failure
; ------------------------------------------------------------------------------
enable_a20:
    push bx
    push cx
    push dx
    push si

    ; 1. Check if A20 is already active
    call check_a20
    test ax, ax
    jnz .a20_success

    ; 2. Try BIOS Function INT 15h, AX=0x2401
    mov ax, 0x2401
    int 0x15
    jc .try_fast_a20                 ; If BIOS call failed, try Fast A20
    test ah, ah
    jnz .try_fast_a20

    call check_a20
    test ax, ax
    jnz .a20_success

.try_fast_a20:
    ; 3. Try Fast A20 Gate via I/O Port 0x92
    ; WARNING: Bit 0 of port 0x92 triggers a hard CPU reset. Never set bit 0!
    in al, 0x92
    test al, 2                       ; Check if bit 1 is already set
    jnz .try_kbc
    or al, 2                         ; Set bit 1 (A20 enable)
    and al, 0xFE                     ; Ensure bit 0 (fast reset) is 0
    out 0x92, al

    ; Short I/O delay
    call io_delay
    call check_a20
    test ax, ax
    jnz .a20_success

.try_kbc:
    ; 4. Try Keyboard Controller (8042) Output Port
    call kbc_wait_write
    mov al, 0xAD                     ; Disable keyboard
    out 0x64, al

    call kbc_wait_write
    mov al, 0xD0                     ; Command: Read output port
    out 0x64, al

    call kbc_wait_read
    in al, 0x60                      ; Read current output port byte
    push ax                          ; Save byte

    call kbc_wait_write
    mov al, 0xD1                     ; Command: Write output port
    out 0x64, al

    call kbc_wait_write
    pop ax
    or al, 2                         ; Set bit 1 (A20 Gate enable)
    out 0x60, al

    call kbc_wait_write
    mov al, 0xAE                     ; Command: Re-enable keyboard
    out 0x64, al

    call io_delay
    call check_a20
    test ax, ax
    jnz .a20_success

    ; Failed all methods
    mov ax, 1
    jmp .a20_exit

.a20_success:
    xor ax, ax                       ; Return 0 for success

.a20_exit:
    pop si
    pop dx
    pop cx
    pop bx
    ret

; ------------------------------------------------------------------------------
; Routine: check_a20
; Tests whether A20 is enabled by checking if 1MB memory wrap-around occurs.
; Compares [0x0000:0x7DFE] with [0xFFFF:0x7E0E].
; 0xFFFF0 + 0x7E0E = 0x107DFE (1 MB + 0x7DFE).
; If A20 is disabled, 0x107DFE wraps to 0x07DFE.
; Returns: AX = 1 if A20 enabled, AX = 0 if A20 disabled (wrapping)
; ------------------------------------------------------------------------------
check_a20:
    pushf
    push ds
    push es
    push di
    push si

    cli                              ; Clear interrupts during test

    xor ax, ax
    mov ds, ax                       ; DS = 0x0000
    mov si, 0x7DFE                   ; DS:SI = 0x0000:0x7DFE

    not ax                           ; AX = 0xFFFF
    mov es, ax                       ; ES = 0xFFFF
    mov di, 0x7E0E                   ; ES:DI = 0xFFFF:0x7E0E (0x107DFE)

    ; Preserve original values
    mov al, [ds:si]
    mov ah, [es:di]

    ; Write test pattern to [ds:si]
    mov byte [ds:si], 0x00
    mov byte [es:di], 0xFF

    ; If A20 is disabled, [ds:si] will now be 0xFF because of wrap-around
    cmp byte [ds:si], 0xFF

    ; Restore original values
    mov [ds:si], al
    mov [es:di], ah

    jne .a20_is_on                   ; Not wrapped -> A20 is enabled!

    ; Wrapped -> A20 is disabled
    xor ax, ax
    jmp .done_check

.a20_is_on:
    mov ax, 1

.done_check:
    pop si
    pop di
    pop es
    pop ds
    popf
    ret

; ------------------------------------------------------------------------------
; Keyboard Controller (8042) Helper Routines
; ------------------------------------------------------------------------------
kbc_wait_write:
    in al, 0x64
    test al, 2                       ; Bit 1: Input buffer status (0 = ready for command)
    jnz kbc_wait_write
    ret

kbc_wait_read:
    in al, 0x64
    test al, 1                       ; Bit 0: Output buffer status (1 = data ready)
    jz kbc_wait_read
    ret

io_delay:
    out 0x80, al                     ; Standard dummy port 0x80 delay
    out 0x80, al
    ret
