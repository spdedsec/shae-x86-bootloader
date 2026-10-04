/* Linker script for 32-bit flat binary kernel payload */
ENTRY(_start)
OUTPUT_FORMAT("binary")

SECTIONS
{
    . = 0x00100000;

    .text : ALIGN(4)
    {
        *(.entry)
        *(.text*)
    }

    .rodata : ALIGN(4)
    {
        *(.rodata*)
    }

    .data : ALIGN(4)
    {
        *(.data*)
    }

    .bss : ALIGN(4)
    {
        *(COMMON)
        *(.bss*)
    }

    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}
