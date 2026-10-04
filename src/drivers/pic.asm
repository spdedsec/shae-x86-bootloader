; ==============================================================================
; SHAE x86 Bootloader - 8259A PIC (Programmable Interrupt Controller) Driver
; ==============================================================================
; Architecture: x86 (32-bit Protected Mode)
; Purpose:      Remaps Master & Slave PIC IRQs to avoid colliding with x86
;               CPU exception vectors (0x00 - 0x1F).
; Mapping:      Master PIC IRQs 0-7  -> Interrupt Vectors 0x20 - 0x27 (32 - 39)
;               Slave PIC  IRQs 8-15 -> Interrupt Vectors 0x28 - 0x2F (40 - 47)
; ==============================================================================

[BITS 32]

global pic_remap
global pic_send_eoi
global pic_mask_all
global pic_unmask_irq

; PIC I/O Ports
PIC1_COMMAND        equ 0x20
PIC1_DATA           equ 0x21
PIC2_COMMAND        equ 0xA0
PIC2_DATA           equ 0xA1

; Initialization Command Words (ICW)
ICW1_ICW4           equ 0x01         ; ICW4 needed
ICW1_INIT           equ 0x10         ; Initialization command
ICW4_8086           equ 0x01         ; 8086/88 mode

; Vector Base Offsets
PIC1_VECTOR_OFFSET  equ 0x20         ; IRQ 0..7 mapped to vectors 0x20..0x27
PIC2_VECTOR_OFFSET  equ 0x28         ; IRQ 8..15 mapped to vectors 0x28..0x2F

section .text

; ------------------------------------------------------------------------------
; Routine: pic_remap
; Reprograms both 8259A PIC chips with proper protected mode vector offsets.
; ------------------------------------------------------------------------------
pic_remap:
    push eax

    ; Save current IRQ masks
    in al, PIC1_DATA
    mov ah, al
    in al, PIC2_DATA
    push eax                         ; AH = PIC1 mask, AL = PIC2 mask

    ; ICW1: Start initialization sequence in cascade mode
    mov al, ICW1_INIT | ICW1_ICW4
    out PIC1_COMMAND, al
    call pic_io_delay
    out PIC2_COMMAND, al
    call pic_io_delay

    ; ICW2: Set Master PIC interrupt vector offset (0x20)
    mov al, PIC1_VECTOR_OFFSET
    out PIC1_DATA, al
    call pic_io_delay

    ; ICW2: Set Slave PIC interrupt vector offset (0x28)
    mov al, PIC2_VECTOR_OFFSET
    out PIC2_DATA, al
    call pic_io_delay

    ; ICW3: Tell Master PIC there is a slave PIC at IRQ2 (0000 0100b = 0x04)
    mov al, 0x04
    out PIC1_DATA, al
    call pic_io_delay

    ; ICW3: Tell Slave PIC its cascade identity (2)
    mov al, 0x02
    out PIC2_DATA, al
    call pic_io_delay

    ; ICW4: Set 8086 mode
    mov al, ICW4_8086
    out PIC1_DATA, al
    call pic_io_delay
    out PIC2_DATA, al
    call pic_io_delay

    ; Mask all hardware interrupts initially (can unmask specific IRQs later)
    mov al, 0xFF
    out PIC1_DATA, al
    out PIC2_DATA, al

    pop eax                          ; Clean stack
    pop eax
    ret

; ------------------------------------------------------------------------------
; Routine: pic_send_eoi
; Sends End of Interrupt (EOI) command to the PICs.
; Input: AL = IRQ number (0..15)
; ------------------------------------------------------------------------------
pic_send_eoi:
    push edx
    push eax

    ; If IRQ came from slave (IRQ >= 8), send EOI to slave PIC
    cmp al, 8
    jb .master_eoi
    mov al, 0x20                     ; EOI command
    out PIC2_COMMAND, al

.master_eoi:
    mov al, 0x20                     ; EOI command to master PIC
    out PIC1_COMMAND, al

    pop eax
    pop edx
    ret

; ------------------------------------------------------------------------------
; Routine: pic_mask_all
; Masks (disables) all 16 hardware IRQs.
; ------------------------------------------------------------------------------
pic_mask_all:
    mov al, 0xFF
    out PIC1_DATA, al
    out PIC2_DATA, al
    ret

; ------------------------------------------------------------------------------
; Routine: pic_unmask_irq
; Unmasks (enables) a specific IRQ line.
; Input: AL = IRQ number (0..15)
; ------------------------------------------------------------------------------
pic_unmask_irq:
    push ecx
    push edx
    push ebx

    movzx ecx, al
    cmp ecx, 8
    jae .unmask_slave

    ; Master PIC (IRQ 0-7)
    in al, PIC1_DATA
    mov bl, 1
    shl bl, cl
    not bl
    and al, bl                       ; Clear mask bit
    out PIC1_DATA, al
    jmp .done_unmask

.unmask_slave:
    ; Slave PIC (IRQ 8-15)
    sub cl, 8
    in al, PIC2_DATA
    mov bl, 1
    shl bl, cl
    not bl
    and al, bl
    out PIC2_DATA, al

    ; Also ensure Master IRQ2 (cascade line) is unmasked
    in al, PIC1_DATA
    and al, ~(1 << 2)
    out PIC1_DATA, al

.done_unmask:
    pop ebx
    pop edx
    pop ecx
    ret

pic_io_delay:
    out 0x80, al
    ret
