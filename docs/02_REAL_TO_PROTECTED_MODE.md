# Chapter 2: Real Mode to 32-Bit Protected Mode Transition

## 1. Real Mode vs. Protected Mode

| Feature | 16-Bit Real Mode (8086) | 32-Bit Protected Mode (IA-32) |
| :--- | :--- | :--- |
| **Addressable Physical Memory** | 1 MB ($2^{20}$ bytes) | 4 GB ($2^{32}$ bytes) |
| **Register Width** | 16-bit (`AX`, `BX`, `SP`, etc.) | 32-bit (`EAX`, `EBX`, `ESP`, etc.) |
| **Memory Addressing** | Segment $\times 16 + \text{Offset}$ | Base + Offset via GDT / Selectors |
| **Hardware Protection** | None (All code runs at Ring 0) | 4 Privilege Rings (Ring 0 to Ring 3) |
| **Paging & Virtual Memory** | Unsupported | Supported (4 KB / 4 MB pages via CR3) |
| **Interrupt Handling** | Real Mode IVT (Vectors 0..255 at `0x0000`) | IDT (256 Gates at arbitrary address) |

---

## 2. The A20 Gate Mystery

### The Historical Bug:
On the Intel 8086 processor, physical memory addresses were computed using 20 address lines ($A_0$ through $A_{19}$):
$$\text{Physical Address} = (\text{Segment} \times 16) + \text{Offset}$$

If a program accessed `0xFFFF:0x0010`:
$$(0xFFFF \times 16) + 0x0010 = 0x0FFFF0 + 0x0010 = 0x100000 \quad (1 \text{ Megabyte})$$

Because the 8086 had only 20 address lines ($A_0 \dots A_{19}$), bit 20 ($A_{20}$) could not be physically asserted on the bus. The high bit was truncated, causing the address to **wrap around to zero**:
$$0x100000 \pmod{2^{20}} = 0x000000$$

Some DOS programmers relied on this wrap-around quirk as an intentional feature.

When IBM introduced the **IBM PC AT (80286)** in 1984, the CPU had 24 address lines ($A_0 \dots A_{23}$), capable of addressing 16 MB. The wrap-around no longer occurred naturally, which broke legacy DOS software.

To maintain backward compatibility, IBM engineers routed the 21st address line ($A_{20}$) through a logic gate controlled by an unused output pin of the **Intel 8042 Keyboard Controller** on the motherboard. By default at boot, $A_{20}$ is held LOW (forced to 0), replicating the 8086 wrap-around bug!

Before switching to 32-bit Protected Mode, the bootloader **must enable the A20 line**; otherwise, odd megabytes of physical memory (`1MB`, `3MB`, `5MB`...) will mirror even megabytes (`0MB`, `2MB`, `4MB`...).

### How SHAE Bootloader Enables A20:
SHAE bootloader implements an exhaustive 4-stage algorithm with software verification:
1. **Verification Test**: Tests if writing to `0xFFFF:0x7E0E` (1 MB + `0x7DFE`) modifies `0x0000:0x7DFE`. If they do not mirror, A20 is already enabled.
2. **BIOS Method**: Calls BIOS INT 15h, `AX = 0x2401`.
3. **Fast A20 Gate**: Directly toggles bit 1 of System Control Port A (`I/O Port 0x92`):
   ```nasm
   in al, 0x92
   or al, 2           ; Set bit 1 (A20 Enable)
   and al, 0xFE       ; Ensure bit 0 (Fast Reset) is NEVER set!
   out 0x92, al
   ```
4. **Keyboard Controller (8042) Method**: Sends commands `0xD0` (read output port) and `0xD1` (write output port) through ports `0x64` and `0x60`.

---

## 3. The Global Descriptor Table (GDT)

In Protected Mode, segment registers no longer represent simple base addresses shifted by 4. Instead, segment registers store **Segment Selectors**: indices into a table of descriptor structures called the **Global Descriptor Table (GDT)**.

### Structure of an 8-Byte GDT Entry:

```
63                 56 55 52 51      48 47          40 39             16 15              0
+--------------------+-----+----------+--------------+-----------------+----------------+
| Base Address 31:24 | G|DB| Limit 19:16| Access Byte | Base Address 23:0|  Limit 15:0    |
+--------------------+-----+----------+--------------+-----------------+----------------+
```

#### Access Byte Breakdown:
- **P (Bit 7)**: Present bit (must be 1 for valid segments).
- **DPL (Bits 6:5)**: Descriptor Privilege Level (`00` = Ring 0 Kernel, `11` = Ring 3 User).
- **S (Bit 4)**: Descriptor type (1 = Code or Data segment, 0 = System segment like TSS).
- **E (Bit 3)**: Executable bit (1 = Code, 0 = Data).
- **DC (Bit 2)**: Direction bit / Conforming bit.
- **RW (Bit 1)**: Readable bit for code / Writable bit for data.
- **A (Bit 0)**: Accessed bit (set by CPU on memory read/write).

#### Flags Breakdown:
- **G (Bit 7)**: Granularity (0 = 1 byte units, 1 = 4 KB page units). With $G=1$ and Limit=`0xFFFFF`, total addressable span is $0x100000 \times 4096 = 4 \text{ Gigabytes}$.
- **DB (Bit 6)**: Size flag (1 = 32-bit protected mode operands, 0 = 16-bit).

### SHAE Flat Memory Layout:
SHAE bootloader configures a **Basic Flat Model** where Code and Data segments cover the entire 4 GB address space starting at physical address `0x00000000`:
- **Selector `0x00`**: Null Descriptor (mandatory 8 zero bytes; CPU faults if dereferenced).
- **Selector `0x08`**: Kernel Code Segment (Base: `0x0`, Limit: `0xFFFFF`, Access: `0x9A`, Flags: `0xCF`).
- **Selector `0x10`**: Kernel Data Segment (Base: `0x0`, Limit: `0xFFFFF`, Access: `0x92`, Flags: `0xCF`).

---

## 4. The Exact Switch Sequence

The transition from Real Mode to Protected Mode requires an atomic sequence of operations:

```nasm
; Step 1: Disable maskable hardware interrupts
cli

; Step 2: Clear direction flag (ensures forward string instructions: movsd, stosb)
cld

; Step 3: Load the GDT descriptor pointer into GDTR register
lgdt [gdt_descriptor]

; Step 4: Enable Protected Mode by setting Bit 0 (PE) of Control Register CR0
mov eax, cr0
or eax, 1            ; Set PE (Protection Enable) flag
mov cr0, eax

; Step 5: Execute far jump to 32-bit Code Segment selector (0x08)
jmp 0x08:protected_mode_entry
```

### Why is the Far Jump Mandatory?
The 80386 and all modern x86 CPUs feature an **instruction prefetch pipeline**. When CR0.PE is set, the CPU pipeline still contains decoded 16-bit real-mode instructions, and the hidden `CS` descriptor cache register still holds 16-bit Real Mode segment limits!

Executing a **far jump (`jmp 0x08:offset`)**:
1. Flushes the instruction prefetch queue.
2. Loads `CS` with selector `0x08`.
3. Loads the hidden descriptor cache of `CS` from GDT entry `0x08` (enabling 32-bit execution mode).

### Step 6: Reloading Data Segment Registers
Upon landing in 32-bit code:
```nasm
[BITS 32]
protected_mode_entry:
    mov ax, 0x10     ; Kernel Data Segment Selector
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    mov esp, 0x90000 ; Dedicated 32-bit stack pointer
```
The CPU is now executing in full 32-bit Protected Mode at Ring 0 with flat 4 GB addressing.
