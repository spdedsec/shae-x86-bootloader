# Chapter 4: Physical Memory Architecture & BIOS E820 Address Map

## 1. The IBM PC Physical Memory Architecture

The physical address space of an x86 computer is partitioned into several distinct architectural zones:

```
+-----------------------------------+ 0xFFFFFFFF (4 GB)
| High BIOS ROM / 32-bit PCI MMIO   |
+-----------------------------------+
| ... Extended Memory (RAM) ...     |
+-----------------------------------+ 0x00100000 (1 MB)
| Motherboard BIOS ROM              | (64 KB: 0xF0000 - 0xFFFFF)
+-----------------------------------+
| Option ROMs (SCSI, Video, NIC)    | (128 KB: 0xC0000 - 0xEFFFF)
+-----------------------------------+
| Color VGA Text Buffer (0xB8000)   | (32 KB: 0xB8000 - 0xBFFFF)
+-----------------------------------+
| EGA/VGA Graphics Framebuffer      | (64 KB: 0xA0000 - 0xAFFFF)
+-----------------------------------+ 0x0009FFFF (640 KB Boundary)
| Extended BIOS Data Area (EBDA)    | (Variable size, typically ~1 KB to 128 KB)
+-----------------------------------+
| Free Conventional RAM (Target)    | (Used for Bootloader stack & Stage 2)
+-----------------------------------+ 0x00008000 (32 KB)
| Stage 2 Loader Buffer             | (0x00008000 - 0x0000FFFF: 32 KB)
+-----------------------------------+ 0x00007E00
| E820 Memory Map Records           | (0x00007E00 - 0x00007FFF: 512 bytes)
+-----------------------------------+ 0x00007C00
| Stage 1 MBR Bootloader            | (512 bytes)
+-----------------------------------+
| Free Low RAM / Real Mode Stack    | (Grows downwards toward 0x0500)
+-----------------------------------+ 0x00000500
| BIOS Data Area (BDA)              | (256 bytes: 0x00400 - 0x004FF)
+-----------------------------------+ 0x00000400
| Real Mode Interrupt Vector Table  | (1,024 bytes: 0x00000 - 0x003FF)
+-----------------------------------+ 0x00000000
```

---

## 2. Why Does an OS Need a Memory Map?

An operating system kernel cannot make assumptions about where physical RAM exists. Modern motherboards contain non-contiguous memory layouts:
- Hardware memory holes (e.g. `15 MB – 16 MB` ISA memory hole).
- Memory-Mapped I/O regions reserved for PCI devices, GPU framebuffers, and motherboard ACPI tables.
- Defective memory blocks marked as bad by firmware.

If a kernel allocates page tables or processes inside reserved ACPI or PCI MMIO space, hardware crashes occur immediately.

Because **BIOS interrupts cannot be called from 32-bit Protected Mode**, the bootloader must query the firmware before switching modes and pass the resulting memory table to the operating system.

---

## 3. BIOS INT 15h, AX=0xE820 Protocol

The gold standard for physical memory discovery on x86 BIOS systems is **INT 15h, AX=0xE820** ("Query System Address Map").

### Registers on Entry:
- `EAX`: Function code = `0x0000E820`.
- `EBX`: Continuation value. Must be set to `0` on the very first call.
- `ES:DI`: Pointer to destination buffer where BIOS writes the 24-byte entry.
- `ECX`: Size of entry buffer (must be $\ge 20$ bytes; pass `24` for ACPI 3.0).
- `EDX`: Magic signature constant = `0x534D4150` (`'SMAP'`).

### Registers on Exit:
- `CF` (Carry Flag): Set if an error occurs or end of list reached.
- `EAX`: Must equal `'SMAP'` (`0x534D4150`) on success.
- `EBX`: Next continuation value. When `EBX == 0`, the entire map has been enumerated.
- `ECX`: Actual number of bytes written by BIOS (typically 20 or 24).

---

## 4. Structure of a 24-Byte E820 Entry

| Byte Offset | Field Name | Data Type | Description |
| :--- | :--- | :--- | :--- |
| `+0` | `BaseAddressLow` | `uint32_t` | Lower 32 bits of region start physical address |
| `+4` | `BaseAddressHigh` | `uint32_t` | Upper 32 bits of region start physical address |
| `+8` | `LengthLow` | `uint32_t` | Lower 32 bits of region length in bytes |
| `+12` | `LengthHigh` | `uint32_t` | Upper 32 bits of region length in bytes |
| `+16` | `Type` | `uint32_t` | Classification of memory region (see below) |
| `+20` | `ACPIAttributes` | `uint32_t` | Extended flags (Bit 0: 1=Valid entry, 0=Ignore) |

### Memory Region Types:
- **Type 1 (`Usable RAM`)**: Free memory available for operating system allocation and kernel page pools.
- **Type 2 (`Reserved`)**: System ROM, motherboard devices, memory-mapped I/O. Never touch!
- **Type 3 (`ACPI Reclaimable`)**: Memory containing ACPI configuration tables. Can be reclaimed by the OS after ACPI parsing.
- **Type 4 (`ACPI NVS`)**: Non-Volatile Storage required by firmware across reboots/sleep states.
- **Type 5 (`Bad Memory`)**: Physical DRAM cells identified as damaged.

---

## 5. SHAE Implementation & Kernel Handshake

In `src/boot/stage2.asm`, the bootloader:
1. Loops over INT 15h, `AX=0xE820`.
2. Stores the valid entry count as a 16-bit word at physical address **`0x00007E00`**.
3. Stores the contiguous array of 24-byte records starting at **`0x00007E08`**.
4. Computes total usable RAM by summing lengths of all Type 1 entries.

When jumping to an external kernel (or the C demonstration payload), the bootloader passes:
- Register `EAX`: Total number of detected E820 memory entries.
- Register `EBX`: 32-bit linear memory pointer to the E820 entry array (`0x7E08`).
