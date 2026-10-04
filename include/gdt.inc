; ==============================================================================
; SHAE x86 Bootloader - Global Descriptor Table (GDT) Definitions
; ==============================================================================

%ifndef GDT_INC
%define GDT_INC

; Segment Selector Offsets in GDT
GDT_NULL_SEL        equ 0x00        ; Null Descriptor (mandatory 0)
GDT_KERNEL_CODE_SEL equ 0x08        ; Ring 0 Code Segment Selector
GDT_KERNEL_DATA_SEL equ 0x10        ; Ring 0 Data Segment Selector
GDT_USER_CODE_SEL   equ 0x18        ; Ring 3 Code Segment Selector (RPL 3 = 0x1B)
GDT_USER_DATA_SEL   equ 0x20        ; Ring 3 Data Segment Selector (RPL 3 = 0x23)

; Access Byte Flags
SEG_DESCTYPE_SYS    equ 0x00        ; System Segment (TSS, LDT, Gate)
SEG_DESCTYPE_CD     equ 0x10        ; Code or Data Segment

SEG_PRES            equ 0x80        ; Present flag
SEG_RING_0          equ 0x00        ; Privilege level 0 (Kernel)
SEG_RING_3          equ 0x60        ; Privilege level 3 (User)

; Code segment types
SEG_CODE_EXRD       equ 0x0A        ; Execute/Read
SEG_CODE_EXRDA      equ 0x0B        ; Execute/Read, accessed

; Data segment types
SEG_DATA_RDWR       equ 0x02        ; Read/Write
SEG_DATA_RDWRA      equ 0x03        ; Read/Write, accessed

; Granularity Flags
SEG_GRAN_4K         equ 0x80        ; 4 KB granularity (limit scaled by 4096)
SEG_SZ_32           equ 0x40        ; 32-bit Protected Mode operand size

%endif ; GDT_INC
