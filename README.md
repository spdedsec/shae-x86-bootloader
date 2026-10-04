# SHAE x86 Bootloader

> **A pedagogical, multistage x86 (IA-32) bootloader and bare-metal operating system runtime written in pure assembly with a secondary C kernel payload demo.**

[![Architecture](https://img.shields.io/badge/Architecture-x86%20IA--32-blue.svg)](#)
[![Assembler](https://img.shields.io/badge/Assembler-NASM%202.16+-orange.svg)](#)
[![Compiler](https://img.shields.io/badge/Compiler-GCC%20Freestanding%20-brightgreen.svg)](#)
[![Mode](https://img.shields.io/badge/Execution-Real%20Mode%20%E2%86%92%2032--bit%20Protected%20Mode-red.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](#)

---

## Table of Contents

1. [Architectural Overview & Philosophy](#1-architectural-overview--philosophy)
2. [Visual Boot Pipeline & Execution Flow](#2-visual-boot-pipeline--execution-flow)
3. [Memory Map & Sector Allocation](#3-memory-map--sector-allocation)
4. [Deep-Dive: How Each Stage Works](#4-deep-dive-how-each-stage-works)
   - [Stage 1: The 512-Byte Master Boot Record (MBR)](#stage-1-the-512-byte-master-boot-record-mbr)
   - [Stage 2: Real Mode Initialization & Protected Mode Switch](#stage-2-real-mode-initialization--protected-mode-switch)
   - [The A20 Line Mystery & Multi-Method Enabler](#the-a20-line-mystery--multi-method-enabler)
   - [BIOS E820 Physical Memory Discovery](#bios-e820-physical-memory-discovery)
   - [Global Descriptor Table (GDT) & Mode Switch](#global-descriptor-table-gdt--mode-switch)
5. [Hardware Subsystems & Drivers](#5-hardware-subsystems--drivers)
   - [8259A Dual PIC Remapping](#8259a-dual-pic-remapping)
   - [Interrupt Descriptor Table (IDT) & Exception Traps](#interrupt-descriptor-table-idt--exception-traps)
   - [VGA 80x25 Color Text Driver (MMIO 0xB8000)](#vga-80x25-color-text-driver-mmio-0xb8000)
   - [16550 UART Serial Communication (COM1 0x3F8)](#16550-uart-serial-communication-com1-0x3f8)
   - [PS/2 Keyboard & Unified Input Multiplexer](#ps2-keyboard--unified-input-multiplexer)
6. [Interactive Diagnostic Shell](#6-interactive-diagnostic-shell)
7. [Demonstration C Kernel Payload (Handshake at 1 MB)](#7-demonstration-c-kernel-payload-handshake-at-1-mb)
8. [Codebase Framework Walkthrough](#8-codebase-framework-walkthrough)
9. [Building, Emulation & Bare-Metal Deployment](#9-building-emulation--bare-metal-deployment)

---

## 1. Architectural Overview & Philosophy

Modern computer architectures boot through a complex chain of transitions. The **SHAE x86 Bootloader** is designed as a clean, transparent, textbook-grade implementation of how an IBM-compatible PC transitions from bare silicon power-on to a fully operational 32-bit Protected Mode environment.

### Core Objectives:
- **No Magic Blobs**: Every single byte from the MBR boot signature (`0xAA55`) to the Protected Mode GDT descriptor is hand-written, documented, and traceable.
- **Fail-Safe Robustness**:
  - Automatic fallback from INT 13h LBA disk packet extensions to legacy CHS reads.
  - Multi-stage A20 gate activation (BIOS, Fast A20, 8042 Keyboard Controller).
  - 256-gate IDT with handlers for CPU traps 0–19, eliminating silent triple faults.
- **Dual Console Telemetry**: All output is synchronously mirrored to both the physical VGA screen (`0xB8000`) and the 16550 UART Serial interface (`COM1`), enabling seamless debugging on real hardware or headless virtual machines (`-nographic`).
- **Clean OS Handshake**: Demonstrates how real operating system kernels (ELF or flat binary) receive machine state, E820 memory maps, and execution control at `0x100000` (1 MB mark).

---

## 2. Visual Boot Pipeline & Execution Flow

```
+-------------------------------------------------------------------------------+
|                       PC Power-On / Electrical Reset                          |
|                       CS:IP = 0xF000:0xFFF0 (0x000FFFF0)                       |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                       Motherboard BIOS POST Execution                         |
|      Constructs IVT (0x0000), BDA (0x0400), checks drives, fires INT 0x19     |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                      Stage 1: MBR Bootloader (0x7C00)                         |
|  - Validates 0xAA55 signature                                                 |
|  - Normalizes segments (DS=ES=SS=0, SP=0x7C00)                                |
|  - Preserves boot drive number from DL register                               |
|  - Reads Stage 2 (32 sectors) from disk to 0x8000 via INT 13h LBA / CHS       |
|  - Verifies Stage 2 magic signature: 'SHAE' (0x53484145)                      |
|  - Jumps to 0x8004                                                            |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                      Stage 2: Setup & Environment (0x8000)                    |
|  - Queries BIOS E820 Physical Memory Map -> stores at 0x7E00 / 0x7E08         |
|  - Unlocks A20 Line (checks wrap-around -> BIOS -> Port 0x92 -> KBC 8042)     |
|  - Reads Kernel payload sectors from disk into staging memory (0x10000)       |
|  - Initializes Video Mode 3 (80x25 text mode) via INT 10h                     |
|  - Prepares Global Descriptor Table (GDT: 4GB Flat Code & Data Descriptors)   |
|  - Disables Interrupts (CLI), loads GDTR, sets CR0.PE bit = 1                 |
|  - Far jump (jmp 0x08:protected_mode_entry) flushes prefetch pipeline         |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
|                  Stage 3: 32-Bit Protected Mode Runtime                       |
|  - Reloads segment selectors (DS, ES, FS, GS, SS = 0x10)                      |
|  - Sets Protected Mode Stack at 0x90000                                       |
|  - Copies Kernel payload from staging (0x10000) to 1 MB (0x100000)            |
|  - Remaps 8259A Dual PIC (Master: 0x20..0x27, Slave: 0x28..0x2F)              |
|  - Builds 256-gate IDT with CPU Exception Handlers (0x00..0x1F)               |
|  - Initializes 16550 UART Serial (COM1 @ 115200 Baud 8N1)                    |
|  - Initializes VGA Text Driver & Cursor Control                               |
|  - Initializes PS/2 Keyboard Driver & Scancode Set 1 Mapper                   |
+---------------------------------------+---------------------------------------+
                                        |
                   +--------------------+--------------------+
                   |                                         |
                   v                                         v
+------------------------------------+   +------------------------------------+
|     SHAE Interactive Shell         |   |    Secondary 32-bit C Kernel       |
|  - help, cpuinfo, mmap, vga,       |   |  - Located at 0x100000 (1 MB)      |
|    dump, reboot, halt, kernel      |   |  - Executed via 'kernel' command   |
+------------------------------------+   +------------------------------------+
```

---

## 3. Memory Map & Sector Allocation

### Physical RAM Layout:

| Physical Address Range | Size | Description |
| :--- | :--- | :--- |
| `0x00000000 - 0x000003FF` | 1 KB | Real Mode Interrupt Vector Table (IVT) |
| `0x00000400 - 0x000004FF` | 256 B | BIOS Data Area (BDA) |
| `0x00000500 - 0x00007BFF` | ~30 KB | Free Conventional Memory (Stage 1 stack grows downward) |
| `0x00007C00 - 0x00007DFF` | 512 B | **Stage 1 Bootloader (MBR)** |
| `0x00007E00 - 0x00007FFF` | 512 B | E820 Memory Map (Count word @ `0x7E00`, Entries @ `0x7E08`) |
| `0x00008000 - 0x0000FFFF` | 32 KB | **Stage 2 Loader & 32-bit Protected Runtime** |
| `0x00010000 - 0x0008FFFF` | 512 KB | Staging Buffer for Disk Payloads |
| `0x00090000 - 0x0009FFFF` | 64 KB | 32-bit Protected Mode Stack (grows down from `0x90000`) |
| `0x000A0000 - 0x000B7FFF` | 96 KB | EGA/VGA Graphics Video Framebuffer |
| `0x000B8000 - 0x000BFFFF` | 32 KB | **Color VGA Text Mode Buffer (80x25)** |
| `0x000C0000 - 0x000FFFFF` | 256 KB | Video BIOS, Option ROMs & Motherboard BIOS |
| `0x00100000 - 0x3FFFFFFF` | Up to 4GB | **Extended Memory (1 MB+) — Kernel Payload Target** |

### Disk Storage Sector Layout (`shae_boot.img`):

| LBA (0-indexed) | 1-indexed Sector | Count | Memory Target | Content |
| :--- | :--- | :--- | :--- | :--- |
| **0** | Sector 1 | 1 sector (512 B) | `0x00007C00` | Stage 1 MBR (Partition Table & `0xAA55`) |
| **1 – 32** | Sectors 2 – 33 | 32 sectors (16 KB) | `0x00008000` | Stage 2, GDT, Drivers, Shell |
| **33 – 96** | Sectors 34 – 97 | 64 sectors (32 KB) | `0x00100000` | C Kernel Payload (`kernel.bin`) |
| **97 – 2879** | Sectors 98 – 2880 | Remaining | Unused | Free disk sectors |

---

## 4. Deep-Dive: How Each Stage Works

### Stage 1: The 512-Byte Master Boot Record (MBR)
The file `src/boot/stage1.asm` is assembled to exactly 512 bytes with origin `0x7C00`.

1. **BPB Compatibility Block**: Standard DOS/FAT dummy header prevents BIOS and partition formatters from clobbering code.
2. **Segment Normalization**: Standardizes segment registers (`DS = ES = SS = 0`) and sets `SP = 0x7C00`.
3. **Drive Number Preservation**: Preserves the BIOS boot drive ID passed in register `DL`.
4. **LBA Disk Loading with CHS Fallback**:
   - Checks for INT 13h Extensions (`AH=0x41`, `BX=0x55AA`).
   - If supported, issues INT 13h `AH=0x42` with a 16-byte Disk Address Packet (DAP).
   - If unsupported, falls back to legacy CHS sector reads (`AH=0x02`).
   - Employs a 3-retry reset loop (`AH=0x00`) to recover from slow-spinning physical drives.
5. **Magic Verification**: Inspects the first 4 bytes of Stage 2 at `0x8000` for the magic signature `0x53484145` (`"SHAE"`). If valid, branches to `0x8004`.
6. **Signature**: Padded to byte 510 with `times 510 - ($ - $$) db 0` followed by `dw 0xAA55`.

### Stage 2: Real Mode Initialization & Protected Mode Switch
The file `src/boot/stage2.asm` executes in 16-bit Real Mode at `0x8000` to utilize BIOS interrupts before they become inaccessible.

### The A20 Line Mystery & Multi-Method Enabler
On the original 8086, addresses wrapped around at 1 MB ($2^{20}$). To retain compatibility on 80286+ chips, IBM routed the 21st address pin ($A_{20}$) through the keyboard controller. If $A_{20}$ is disabled, physical memory accesses to odd megabytes wrap around.

`src/boot/a20.asm` implements an exhaustive enabler:
- **Wrap-around Test**: Compares memory byte at `0x0000:0x7DFE` with `0xFFFF:0x7E0E` (1 MB + `0x7DFE`).
- **Method 1**: BIOS INT 15h, `AX=0x2401`.
- **Method 2**: Fast A20 Gate via System Control Port A (`0x92`). Bit 1 is asserted, while ensuring bit 0 (fast reset) remains zero.
- **Method 3**: 8042 Keyboard Controller output port manipulation via ports `0x64` and `0x60`.

### BIOS E820 Physical Memory Discovery
Before disabling Real Mode, `detect_memory_e820` queries BIOS INT 15h, `AX=0xE820` with the `'SMAP'` magic constant (`0x534D4150`).
- Each returned 24-byte record details physical Base Address (64-bit), Length (64-bit), and Region Type (Usable RAM, Reserved, ACPI, Bad).
- The records are cached at `0x7E08`, and the count is stored at `0x7E00`.

### Global Descriptor Table (GDT) & Mode Switch
In Protected Mode, segment registers point to descriptors in the GDT. SHAE bootloader constructs a flat memory model:
- **Descriptor 0 (`0x00`)**: Mandatory Null Descriptor.
- **Descriptor 1 (`0x08`)**: Kernel Code Segment (Base: `0x0`, Limit: `4 GB`, Ring 0, 32-bit Executable/Readable).
- **Descriptor 2 (`0x10`)**: Kernel Data Segment (Base: `0x0`, Limit: `4 GB`, Ring 0, 32-bit Writable).
- **Descriptor 3 & 4 (`0x18`, `0x20`)**: User-mode Code and Data descriptors.

The switch:
```nasm
cli                      ; 1. Disable interrupts
cld                      ; 2. Clear direction flag
lgdt [gdt_descriptor]    ; 3. Load GDTR with 32-bit linear address
mov eax, cr0
or eax, 1                ; 4. Set Protection Enable (PE) bit
mov cr0, eax
jmp 0x08:stage3_entry    ; 5. Far jump flushes pipeline and sets CS = 0x08
```

---

## 5. Hardware Subsystems & Drivers

### 8259A Dual PIC Remapping (`src/drivers/pic.asm`)
The legacy IBM PC mapped Master PIC hardware IRQs 0–7 to vectors `0x08..0x0F`. On 386+, Intel reserved vectors `0x00..0x1F` for CPU architecture exceptions (Double Fault, GPF, Page Fault).
- SHAE reprograms the cascaded 8259A PIC chips via ICW1–ICW4.
- **Master PIC**: Remapped to vectors `0x20..0x27` (IRQs 0–7).
- **Slave PIC**: Remapped to vectors `0x28..0x2F` (IRQs 8–15).

### Interrupt Descriptor Table (IDT) & Exception Traps (`src/drivers/idt.asm`)
Without an IDT, any CPU exception triggers an unhandled Double Fault (#DF), leading directly to an uncontrollable **Triple Fault** and instant hardware reboot.
- SHAE constructs a 256-entry IDT.
- Installs 32-bit interrupt gates (`0x8E`) for CPU traps 0 through 19 (Division by Zero, Debug, NMI, Breakpoint, Overflow, Bound Range, Invalid Opcode, Double Fault, GPF, Page Fault, etc.).
- When an exception occurs, a diagnostic kernel panic screen is printed with the exact exception name, and the CPU is safely halted (`cli; hlt`).

### VGA 80x25 Color Text Driver (`src/drivers/vga.asm`)
Direct Memory-Mapped I/O at physical address `0x000B8000`:
- 2 bytes per cell: ASCII character + Color Attribute byte.
- Supports `\n` (newline), `\r` (carriage return), `\b` (backspace), `\t` (tab).
- Hardware cursor tracking via CRT Controller ports `0x3D4` and `0x3D5`.
- Automatic screen scrolling when rows exceed row 24.

### 16550 UART Serial Communication (`src/drivers/serial.asm`)
Configures **COM1** at I/O port `0x03F8`:
- Baud Rate: 115,200 Baud (Divisor = 1).
- Framing: 8 Data Bits, No Parity, 1 Stop Bit (8N1).
- 14-byte FIFO buffer enabled.
- Dual Output Helper (`kprint`): Synchronously mirrors text to both VGA and Serial.

### PS/2 Keyboard Driver (`src/drivers/keyboard.asm`)
- Reads scan codes from port `0x60`, status from port `0x64`.
- Converts Scancode Set 1 make/break codes to ASCII.
- Tracks Left and Right Shift states.
- Dual input multiplexer: accepts input transparently from both PS/2 hardware keyboards and serial terminal stdin.

---

## 6. Interactive Diagnostic Shell

Upon initialization, the bootloader starts the **SHAE Interactive Shell** (`src/kernel/shell.asm`):

```text
================================================================================
  ____  _   _    _    _____            ___   ___   _    
 / ___|| | | |  / \  | ____|          / _ \ / _ \ / |   
 \___ \| |_| | / _ \ |  _|   ______  | (_) | | | || |   
  ___) |  _  |/ ___ \| |___ |______|  \__, | |_| || |   
 |____/|_| |_/_/   \_\_____|            /_/ \___/ |_|   
        SHAE Multistage x86 Protected Mode Bootloader (v1.0)                     
================================================================================
[STATUS] Mode: 32-bit Protected | A20: Active | GDT: Flat 4GB | IDT: Loaded
Type 'help' to view available diagnostic commands.

shae> 
```

### Supported Shell Commands:

| Command | Description |
| :--- | :--- |
| `help` | Lists all available diagnostic commands. |
| `cpuinfo` | Queries CPUID: processor vendor string, brand model name, and feature flags (FPU, MMX, SSE, SSE2, PAE, APIC, and 64-bit Long Mode capability). |
| `mmap` | Formats and dumps the BIOS E820 physical memory map table and calculates total detected usable RAM. |
| `vga` | Displays an interactive 16-color VGA text palette matrix. |
| `dump` | Performs a hexadecimal and ASCII memory dump of physical memory (defaults to MBR boot sector at `0x7C00`). |
| `clear` | Clears the VGA console screen and resets cursor to (0, 0). |
| `about` | Displays architecture and design overview. |
| `kernel` | Transfers execution control to the secondary 32-bit C Kernel payload loaded at `0x100000` (1 MB mark). |
| `reboot` | Pulses 8042 keyboard controller reset line (port `0x64`, command `0xFE`) to reboot the computer. |
| `halt` | Halts CPU execution safely (`cli; hlt`). |

---

## 7. Demonstration C Kernel Payload (Handshake at 1 MB)

Located in `src/payload_c/`, this component demonstrates how an external operating system kernel interfaces with the SHAE Bootloader:

- **Entry Point**: `src/payload_c/entry.asm` sets up the C calling convention stack.
- **Parameters Received**:
  - `EAX`: Total number of detected E820 memory map records.
  - `EBX`: 32-bit physical address pointing to the memory map record array (`0x7E08`).
- **Target Location**: Linked with `src/payload_c/linker.ld` to execute at **`0x00100000` (1 MB)**.
- **Kernel Code (`kernel.c`)**:
  - Direct port I/O routines (`inb`, `outb`).
  - Serial and VGA printing functions.
  - Verifies successful transition and control handoff.

```c
void c_kernel_main(uint32_t mmap_count, struct e820_entry* mmap_table) {
    serial_puts("[KERNEL] Successfully executing at 0x100000 in 32-bit Protected Mode!\n");
    vga_puts("[KERNEL] Handshake verified: Bootloader -> Kernel complete.\n", 0x0A);
}
```

---

## 8. Codebase Framework Walkthrough

```text
shae-x86-bootloader/
├── Makefile                    # Automated build, test, and QEMU emulation targets
├── README.md                   # This comprehensive teaching guide
├── .gitignore                  # Git ignore rules for build artifacts
│
├── include/                    # Shared assembly definitions & headers
│   ├── boot.inc                # Memory constants, sector geometry, magic constants
│   ├── gdt.inc                 # GDT selector offsets and descriptor flags
│   ├── vga.inc                 # VGA video memory (0xB8000), colors, CRT ports
│   └── serial.inc              # 16550 UART COM1 (0x3F8) registers and divisors
│
├── src/
│   ├── boot/
│   │   ├── stage1.asm          # 512-byte MBR bootloader with LBA/CHS loading
│   │   ├── stage2.asm          # Extended loader: E820 map, A20 gate, GDT, 32-bit switch
│   │   └── a20.asm             # Multi-method A20 line controller and wrap-around test
│   │
│   ├── drivers/
│   │   ├── vga.asm             # 32-bit VGA 80x25 text driver, colors, cursor, scrolling
│   │   ├── serial.asm          # 32-bit 16550 UART COM1 serial driver & dual-output kprint
│   │   ├── pic.asm             # 8259A Dual PIC initialization and vector remapper
│   │   ├── idt.asm             # 256-gate IDT & ISR handlers for CPU exceptions 0-19
│   │   └── keyboard.asm        # PS/2 keyboard driver & serial input multiplexer
│   │
│   ├── kernel/
│   │   ├── kernel_entry.asm    # 32-bit subsystem initialization & shell launcher
│   │   ├── shell.asm           # Interactive diagnostic command-line interface
│   │   ├── cpuinfo.asm         # CPUID detector (vendor, model, 64-bit Long Mode flag)
│   │   └── mmap.asm            # E820 memory map parser and usable RAM calculator
│   │
│   └── payload_c/
│       ├── entry.asm           # Assembly entry stub for C kernel payload
│       ├── kernel.c            # Standalone demonstration 32-bit C operating system kernel
│       └── linker.ld           # GNU Linker script locating kernel at 0x100000 (1 MB)
│
├── docs/                       # In-depth educational documentation chapters
│   ├── 01_BOOT_PROCESS.md      # Silicon reset vector to 0x7C00 and MBR mechanics
│   ├── 02_REAL_TO_PROTECTED_MODE.md # Real mode segmentation, A20, GDT, and CR0.PE
│   ├── 03_HARDWARE_DRIVERS.md  # VGA 0xB8000, UART 0x3F8, PIC remapping, IDT gates
│   └── 04_MEMORY_AND_E820.md   # Physical RAM layout, BDA, and BIOS E820 structure
│
└── scripts/
    └── run_qemu.sh             # Helper runner for GUI, headless, curses, and debug modes
```

---

## 9. Building, Emulation & Bare-Metal Deployment

### Prerequisites:
- `nasm` (Netwide Assembler, version 2.14+)
- `gcc` (with 32-bit freestanding support: `gcc -m32`)
- `ld` (GNU Linker with `elf_i386` emulation)
- `qemu-system-x86_64` (for emulation and automated testing)

### Build Commands:
```bash
# Build bootable raw disk image (build/shae_boot.img)
make

# Run automated functional test suite (verifies boot, CPUID, E820, and C Kernel)
make test

# Launch in QEMU with graphical window and serial stdio
make run

# Launch in headless serial mode (ideal for remote servers / SSH)
make run-headless

# Launch in terminal curses mode
make run-curses

# Start QEMU paused with GDB remote debugging server on localhost:1234
make debug

# Clean all build outputs
make clean
```

### Bare-Metal USB Deployment:
You can boot SHAE on real x86 PC hardware using a USB flash drive.

> [!CAUTION]
> The `dd` command directly overwrites raw disk sectors. Double-check your target drive identifier (e.g. `/dev/sdX`) using `lsblk` before running to avoid overwriting your primary operating system!

```bash
# Identify your USB drive
lsblk

# Write the bootloader disk image to the USB drive
sudo dd if=build/shae_boot.img of=/dev/sdX bs=512 status=progress conv=fsync
```

Insert the USB drive into any x86 PC with Legacy BIOS / CSM (Compatibility Support Module) enabled in UEFI settings, and boot from the USB drive.

---

## License

This project is licensed under the MIT License. Feel free to use, study, fork, and build your own operating system on top of it.
