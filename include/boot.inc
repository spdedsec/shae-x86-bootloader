; ==============================================================================
; SHAE x86 Bootloader - System Definitions & Memory Map Constants
; ==============================================================================

%ifndef BOOT_INC
%define BOOT_INC

; ------------------------------------------------------------------------------
; Memory Map Constants (x86 Real & Protected Mode)
; ------------------------------------------------------------------------------
STAGE1_LOAD_ADDR     equ 0x7C00     ; Standard BIOS boot sector load address
STAGE1_STACK_TOP     equ 0x7C00     ; Real mode stack grows downward from 0x7C00

MMAP_BUFFER_ADDR     equ 0x7E00     ; Storage for E820 memory map info
MMAP_COUNT_ADDR      equ 0x7E00     ; Word: number of E820 entries detected
MMAP_ENTRIES_ADDR    equ 0x7E08     ; Array of 24-byte E820 entries

STAGE2_LOAD_ADDR     equ 0x8000     ; Stage 2 entry address in RAM (0x0000:0x8000)
STAGE2_SECTOR_START  equ 2          ; 1-indexed sector (LBA 1, sector 2 on disk)
STAGE2_SECTOR_COUNT  equ 32         ; Number of sectors allocated for Stage 2 (16 KB)

PROTECTED_STACK_TOP  equ 0x90000    ; Top of stack in 32-bit Protected Mode (below BDA/VGA)

KERNEL_LOAD_ADDR     equ 0x100000   ; 1 MB mark (Where modern 32-bit kernels reside)
KERNEL_SECTOR_START  equ 34         ; 1-indexed sector number
KERNEL_LBA_START     equ 33         ; 0-indexed LBA (LBA 33)
KERNEL_SECTOR_COUNT  equ 64         ; Up to 32 KB kernel payload

; ------------------------------------------------------------------------------
; Signatures and Magic Values
; ------------------------------------------------------------------------------
STAGE2_MAGIC         equ 0x53484145 ; ASCII "SHAE" (0x53='S', 0x48='H', 0x41='A', 0x45='E')
MBR_MAGIC            equ 0xAA55     ; Standard PC BIOS boot signature

%endif ; BOOT_INC
