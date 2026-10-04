/* ==============================================================================
 * SHAE x86 Bootloader - Demonstration 32-bit C Kernel Payload
 * ==============================================================================
 * Target:       IA-32 (x86 32-bit Protected Mode)
 * Memory Base:  0x00100000 (1 MB mark)
 * Parameters:   EAX = E820 Memory Map Count, EBX = E820 Memory Map Buffer Pointer
 * ============================================================================== */

typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;

#define VGA_MEMORY ((volatile uint16_t*)0xB8000)
#define VGA_COLS 80
#define VGA_ROWS 25
#define COM1_PORT 0x3F8

/* E820 Memory Map Record Structure */
struct e820_entry {
    uint32_t base_low;
    uint32_t base_high;
    uint32_t length_low;
    uint32_t length_high;
    uint32_t type;
    uint32_t acpi_attr;
} __attribute__((packed));

/* Hardware Port I/O Helpers */
static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

/* Serial UART Output */
static void serial_putc(char c) {
    while ((inb(COM1_PORT + 5) & 0x20) == 0);
    outb(COM1_PORT, c);
}

static void serial_puts(const char* s) {
    while (*s) {
        if (*s == '\n') serial_putc('\r');
        serial_putc(*s++);
    }
}

/* VGA Output Helpers */
static uint32_t cursor_row = 18;
static uint32_t cursor_col = 0;

static void vga_putc(char c, uint8_t color) {
    if (c == '\n') {
        cursor_col = 0;
        cursor_row++;
        return;
    }
    if (cursor_row >= VGA_ROWS) {
        cursor_row = VGA_ROWS - 1;
    }
    VGA_MEMORY[cursor_row * VGA_COLS + cursor_col] = ((uint16_t)color << 8) | (uint8_t)c;
    cursor_col++;
    if (cursor_col >= VGA_COLS) {
        cursor_col = 0;
        cursor_row++;
    }
}

static void vga_puts(const char* s, uint8_t color) {
    while (*s) {
        vga_putc(*s++, color);
    }
}

/* Main C Kernel Entry Point */
void c_kernel_main(uint32_t mmap_count, struct e820_entry* mmap_table) {
    const char banner[] =
        "\n"
        "================================================================================\n"
        "                >>> SHAE DEMO C KERNEL PAYLOAD BOOTED <<<                       \n"
        "================================================================================\n";

    serial_puts(banner);
    serial_puts("[KERNEL] Successfully executing at 0x100000 (1MB) in 32-bit Protected Mode!\n");
    serial_puts("[KERNEL] Control passed successfully from SHAE Bootloader to C Kernel.\n");

    vga_puts(banner, 0x1F); // White on Blue
    vga_puts("[KERNEL] Executing at 0x100000 (1MB) in 32-bit Protected Mode!\n", 0x0A);
    vga_puts("[KERNEL] Handshake verified: Bootloader -> Kernel transition complete.\n", 0x0E);

    /* Return cleanly back to the SHAE Shell */
}
