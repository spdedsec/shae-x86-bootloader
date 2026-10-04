# Chapter 3: Bare-Metal Hardware Interfacing & Subsystem Drivers

Once the CPU enters 32-bit Protected Mode, **BIOS interrupts (`int 0x10`, `int 0x13`, `int 0x15`) are no longer callable**, because BIOS routines were assembled as 16-bit Real Mode code.

To interact with the outside world, the bootloader must communicate directly with hardware controllers via **Memory-Mapped I/O (MMIO)** and **Port-Mapped I/O (`in` / `out` instructions)**.

---

## 1. VGA Text Mode 80x25 Driver (MMIO at 0xB8000)

The standard PC video subsystem reserves memory range `0x000B8000` to `0x000BFFFF` (32 KB) for color text display buffers.

In standard **VGA Mode 3 (80 columns $\times$ 25 rows)**:
- Total cells: $80 \times 25 = 2,000\text{ characters}$.
- Each cell requires exactly **2 bytes** of physical video RAM:
  - **Byte 0**: ASCII Character Code (e.g. `'A'` = `0x41`).
  - **Byte 1**: Color Attribute Byte.

### Attribute Byte Bit Layout:
```
  7       6   5   4       3       2   1   0
+-------+-----------+-------+-----------+
| Blink | BG Color  | Bright| FG Color  |
+-------+-----------+-------+-----------+
```
- Bits [3:0]: Foreground Color (16 colors: 0=Black, 1=Blue, ..., 15=White).
- Bits [6:4]: Background Color (8 colors: 0=Black, ..., 7=Light Gray).
- Bit 7: Blinking or High Intensity Background.

### Linear Video Address Calculation:
To write a character at row $y$ and column $x$:
$$\text{Address} = 0x000B8000 + 2 \times (y \times 80 + x)$$

### Hardware Cursor Control via CRTC Registers:
The blinking hardware cursor position is maintained by the VGA CRT Controller via I/O ports `0x3D4` (Index Register) and `0x3D5` (Data Register):
- Cursor Location High Byte: Index `0x0E`.
- Cursor Location Low Byte: Index `0x0F`.

```nasm
; Reposition cursor to offset = row * 80 + col
mov edx, 0x03D4
mov al, 0x0F          ; Low byte index
out dx, al
mov edx, 0x03D5
mov al, [cursor_offset_low]
out dx, al

mov edx, 0x03D4
mov al, 0x0E          ; High byte index
out dx, al
mov edx, 0x03D5
mov al, [cursor_offset_high]
out dx, al
```

---

## 2. 16550 UART Serial Communication Driver (COM1)

Serial ports communicate via RS-232 / UART chips. The primary serial port **COM1** is mapped to base I/O port **`0x03F8`**.

Serial communication is invaluable in OS and bootloader development:
- It produces real-time debug telemetry even if the video display is corrupted or uninitialized.
- In QEMU, the `-serial stdio` flag forwards all COM1 output directly to the terminal stdout.

### Register Map (Offset from Base 0x3F8):
| Offset | DLAB | Register Name | Description |
| :--- | :--- | :--- | :--- |
| `+0` | 0 | Data Register (RBR / THR) | Read: Received byte; Write: Transmit byte |
| `+0` | 1 | Divisor Latch Low (DLL) | Low byte of baud rate divisor |
| `+1` | 0 | Interrupt Enable (IER) | Interrupt triggers |
| `+1` | 1 | Divisor Latch High (DLM) | High byte of baud rate divisor |
| `+2` | X | FIFO Control (FCR) | FIFO enable, queue reset, threshold |
| `+3` | X | Line Control (LCR) | Data bits, parity, stop bits, DLAB bit |
| `+4` | X | Modem Control (MCR) | RTS / DSR signals, loopback |
| `+5` | X | Line Status (LSR) | Transmission & reception buffer status |

### Baud Rate Calculation:
The 16550 UART uses a master clock oscillator of $1.8432\text{ MHz}$, internally divided by 16 ($115,200\text{ Hz}$):
$$\text{Divisor} = \frac{115,200}{\text{Desired Baud Rate}}$$
For $115,200\text{ Baud}$: $\text{Divisor} = \frac{115200}{115200} = 1$.

---

## 3. 8259A PIC Cascade Remapping

The original IBM PC motherboard used two cascaded **8259A Programmable Interrupt Controllers**:
- **Master PIC**: I/O ports `0x20` (Command) and `0x21` (Data).
- **Slave PIC**: I/O ports `0xA0` (Command) and `0xA1` (Data), wired into IRQ2 of the Master.

### The Conflict Problem:
In IBM Real Mode, the BIOS mapped Master IRQs 0..7 to interrupt vectors `0x08..0x0F`.
However, the Intel 80386 architecture reserved interrupt vectors `0x00..0x1F` exclusively for CPU exceptions:
- Vector `0x08`: **Double Fault Exception (#DF)**.
- Vector `0x0D`: **General Protection Fault (#GP)**.
- Vector `0x0E`: **Page Fault (#PF)**.

If the PIC is not remapped in Protected Mode, every hardware timer tick (IRQ0) triggers interrupt vector `0x08`, which the CPU interprets as a Double Fault, resulting in an immediate crash!

### The Solution:
SHAE bootloader remaps the PICs:
- **Master PIC IRQs 0..7** $\rightarrow$ Vectors **`0x20..0x27`** (decimal 32..39).
- **Slave PIC IRQs 8..15** $\rightarrow$ Vectors **`0x28..0x2F`** (decimal 40..47).

This moves all hardware interrupts safely above the 32 reserved architectural CPU exception vectors.

---

## 4. Interrupt Descriptor Table (IDT) & Exception Handling

The **Interrupt Descriptor Table (IDT)** defines how the CPU responds to hardware interrupts, software interrupts (`int n`), and CPU exceptions.

Each of the 256 IDT gates is an **8-byte structure**:
```
Bytes 0..1: Offset bits [15:0] of the Interrupt Service Routine (ISR)
Bytes 2..3: Code Segment Selector in the GDT (0x08)
Byte 4:     Reserved (0)
Byte 5:     Attributes (0x8E = 32-bit Interrupt Gate, Ring 0, Present)
Bytes 6..7: Offset bits [31:16] of the ISR
```

### Preventing Triple Faults:
If a CPU fault occurs (e.g. division by zero, corrupted memory pointer) without a registered IDT gate:
1. The CPU raises the initial fault (e.g. #UD or #GP).
2. Because the handler cannot be resolved, the CPU raises a **Double Fault (#DF, vector 8)**.
3. Because the Double Fault handler is missing, the CPU triggers a **Triple Fault**.
4. Upon a Triple Fault, x86 hardware halts and immediately asserts the motherboard reset line, rebooting the machine!

SHAE bootloader installs dedicated handlers for CPU exceptions 0 through 19. When an exception occurs, execution is safely intercepted, a detailed diagnostic panic banner is printed with the exact exception name, and the CPU halts safely (`cli; hlt`) without rebooting.
