# Chapter 1: The x86 Boot Process — Silicon to Master Boot Record

## 1. Physical Reset Vector: What Happens at Power-On?

When you press the power button on an x86 PC or start a virtual machine like QEMU, the central processing unit (CPU) begins execution in a special hardware state known as **16-bit Real Mode**.

In Real Mode, the processor emulates the behavior of the original 1978 Intel 8086 CPU:
- 16-bit register widths (`AX`, `BX`, `CX`, `DX`, `SI`, `DI`, `BP`, `SP`).
- 20-bit physical address bus, limiting accessible physical RAM to exactly $2^{20}$ bytes = **1 Megabyte** (`0x00000000` to `0x000FFFFF`).
- No virtual memory, no hardware paging, and no memory protection (Ring 0 privileges everywhere).

### The Reset Vector
At electrical reset, the CPU registers are initialized by hardware:
- `CS` (Code Segment) = `0xF000`
- `IP` (Instruction Pointer) = `0xFFF0` (on 8086/80286) or `EIP` base = `0xFFFF0000` with selector hidden base pointing to `0xFFFF0000` (on 386+).
- The resulting physical entry address is **`0x000FFFF0`** (16 bytes before the 1 MB boundary).

Located at `0x000FFFF0` is a far jump instruction in the motherboard BIOS ROM pointing to the motherboard's **Power-On Self-Test (POST)** firmware code.

---

## 2. BIOS POST & Boot Device Selection

During POST, the BIOS:
1. Verifies system integrity (CPU, CMOS RTC, DRAM controller, PCI/PCIe buses).
2. Sets up basic hardware controllers (interrupt controller, video display, keyboard).
3. Constructs the **Interrupt Vector Table (IVT)** at `0x0000:0x0000` (1024 bytes) and the **BIOS Data Area (BDA)** at `0x0040:0x0000`.
4. Initializes the default display controller (VGA Mode 3: 80x25 text mode).
5. Scans configured boot devices (floppy drives, hard drives, USB flash drives, CD-ROMs, network PXE) according to the boot order set in CMOS.

When a bootable storage medium is detected, the BIOS issues **INT 0x19** (Bootstrap Loader Service).

---

## 3. The 0x7C00 Magic Origin: Why 0x7C00?

The BIOS reads the very first 512-byte sector (Logical Block Address 0) of the selected drive into RAM at:
$$\text{Segment } 0x0000 : \text{Offset } 0x7C00 \quad (\text{Physical Address } 0x07C00)$$

### Historical Context:
In 1981, the original IBM PC 5150 shipped with a minimum configuration of **32 Kilobytes (32,768 bytes)** of RAM:
- `0x00000` – `0x003FF` (1,024 bytes): Real Mode IVT.
- `0x00400` – `0x004FF` (256 bytes): BIOS Data Area (BDA).
- `0x00500` – `0x07BFF` (~30 KB): Free conventional RAM.
- `0x07C00` – `0x07DFF` (512 bytes): The Boot Sector load address.
- `0x07E00` – `0x07FFF` (512 bytes): Stack space growing downwards from `0x7C00`.
- `0x08000` (32 KB mark): The memory limit of the base machine!

The IBM BIOS engineers placed the boot sector exactly 1024 bytes below the end of a 32 KB machine so that the operating system bootloader had maximal contiguous memory below it (`0x0500` to `0x07BFF`) and stack room immediately around it without colliding with BIOS data structures.

---

## 4. Master Boot Record (MBR) Anatomy

A valid MBR is precisely 512 bytes long:

```
+-------------------------------------------------------------------+
| Bytes 0x000 - 0x002  | Jump Instruction (jmp short start; nop)    | (3 bytes)
+-------------------------------------------------------------------+
| Bytes 0x003 - 0x03D  | BIOS Parameter Block (BPB / FAT Header)    | (59 bytes)
+-------------------------------------------------------------------+
| Bytes 0x03E - 0x1BD  | Bootloader Executable Code & Data          | (384 bytes)
+-------------------------------------------------------------------+
| Bytes 0x1BE - 0x1FD  | Master Partition Table (4 x 16-byte entries)| (64 bytes)
+-------------------------------------------------------------------+
| Bytes 0x1FE - 0x1FF  | Boot Signature: 0x55, 0xAA (Little-Endian) | (2 bytes)
+-------------------------------------------------------------------+
```

### The Boot Signature: `0xAA55`
Before executing the loaded sector, the BIOS tests the last two bytes:
```nasm
cmp word [0x7DFE], 0xAA55
```
Because x86 is **little-endian**, the low byte `0x55` comes first at byte 510, and the high byte `0xAA` comes at byte 511.
- If the signature matches: the BIOS executes `jmp 0x0000:0x7C00`, passing the boot drive number in register `DL` (`0x00` = floppy drive, `0x80` = first hard drive).
- If the signature does not match: the BIOS displays `"No bootable device found"` or attempts the next device.

---

## 5. Segment Normalization & Stack Setup

When the BIOS branches to `0x7C00`, register state is unpredictable across different BIOS vendors:
- Some BIOSes jump to `0x0000:0x7C00` (`CS = 0x0000`, `IP = 0x7C00`).
- Other BIOSes jump to `0x07C0:0x0000` (`CS = 0x07C0`, `IP = 0x0000`). Both evaluate to physical address `0x07C00`!

Therefore, the first task of `stage1.asm` is segment normalization:
```nasm
start:
    cli                      ; Disable interrupts while stack is modified
    xor ax, ax               ; AX = 0x0000
    mov ds, ax               ; Data Segment = 0x0000
    mov es, ax               ; Extra Segment = 0x0000
    mov ss, ax               ; Stack Segment = 0x0000
    mov sp, 0x7C00           ; Stack Pointer grows downwards from 0x7C00
    sti                      ; Re-enable interrupts
    mov [boot_drive], dl     ; Preserve BIOS boot drive identifier
```

By pointing `SS:SP` to `0x0000:0x7C00`, pushed stack values grow downwards through free memory (`0x7BFE`, `0x7BFC`...) toward `0x0500`, safely away from our code.

---

## 6. Stage 2 Loading via BIOS Disk Services

Because the MBR is constrained to 512 bytes, complex operating system initialization (A20 gate, memory detection, protected mode switching, GDT, IDT, drivers) cannot fit in Stage 1.

Stage 1 acts as a **first-stage loader**: its sole responsibility is reading Stage 2 from the sectors immediately following the MBR into memory at `0x8000`.

### LBA vs. CHS Disk Access
1. **LBA (Logical Block Addressing)**: Treats the disk as a flat array of numbered 512-byte blocks (0, 1, 2, ...). Accessed via BIOS INT 13h Extension (`AH = 0x42`) with a **Disk Address Packet (DAP)** structure:
```nasm
align 4
dap:
    db 0x10                  ; Size of packet (16 bytes)
    db 0x00                  ; Reserved (must be 0)
    dw 32                    ; Number of sectors to transfer
    dw 0x8000                ; Memory offset destination
    dw 0x0000                ; Memory segment destination
    dq 1                     ; Starting LBA (Sector 1 = 2nd physical sector)
```
2. **CHS (Cylinder-Head-Sector)**: Legacy disk geometry addressing. Accessed via BIOS INT 13h (`AH = 0x02`). Used as an automatic fallback if a legacy BIOS lacks INT 13h extensions.
