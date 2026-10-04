# ==============================================================================
# SHAE x86 Bootloader - Master Makefile
# ==============================================================================

# Toolchain definitions
NASM        ?= nasm
CC          ?= gcc
LD          ?= ld
QEMU        ?= qemu-system-x86_64

# Compilation flags
NASM_FLAGS  = -I include/
CFLAGS      = -m32 -ffreestanding -fno-pie -fno-pic -fno-stack-protector -nostdlib -Wall -Wextra -I include/
LDFLAGS     = -m elf_i386

# Directory layout
SRC_DIR     = src
BUILD_DIR   = build
INC_DIR     = include
SCRIPTS_DIR = scripts

# Targets
STAGE1_SRC  = $(SRC_DIR)/boot/stage1.asm
STAGE2_SRC  = $(SRC_DIR)/boot/stage2.asm
C_ENTRY_SRC = $(SRC_DIR)/payload_c/entry.asm
C_KERN_SRC  = $(SRC_DIR)/payload_c/kernel.c
LINKER_SCR  = $(SRC_DIR)/payload_c/linker.ld

STAGE1_BIN  = $(BUILD_DIR)/stage1.bin
STAGE2_BIN  = $(BUILD_DIR)/stage2.bin
KERNEL_BIN  = $(BUILD_DIR)/kernel.bin
BOOT_IMG    = $(BUILD_DIR)/shae_boot.img

# Sector counts
STAGE2_SECTORS = 32
KERNEL_SECTORS = 64
TOTAL_SECTORS  = 2880   # 1.44 MB standard floppy/disk image

.PHONY: all clean run run-headless run-curses debug gdb test help

all: $(BOOT_IMG)

# ------------------------------------------------------------------------------
# Build Pipeline
# ------------------------------------------------------------------------------

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Assemble Stage 1 (MBR - 512 bytes)
$(STAGE1_BIN): $(STAGE1_SRC) $(INC_DIR)/boot.inc | $(BUILD_DIR)
	$(NASM) $(NASM_FLAGS) -f bin $< -o $@
	@sz=$$(stat -c %s $@); \
	if [ $$sz -ne 512 ]; then \
		echo "ERROR: Stage 1 MBR must be exactly 512 bytes! Current size: $$sz bytes"; \
		exit 1; \
	fi; \
	echo "[OK] Stage 1 MBR assembled: 512 bytes"

# Assemble Stage 2 & 32-bit Protected Subsystems
$(STAGE2_BIN): $(STAGE2_SRC) $(SRC_DIR)/boot/a20.asm \
               $(SRC_DIR)/drivers/vga.asm $(SRC_DIR)/drivers/serial.asm \
               $(SRC_DIR)/drivers/pic.asm $(SRC_DIR)/drivers/idt.asm \
               $(SRC_DIR)/drivers/keyboard.asm $(SRC_DIR)/kernel/cpuinfo.asm \
               $(SRC_DIR)/kernel/mmap.asm $(SRC_DIR)/kernel/shell.asm \
               $(SRC_DIR)/kernel/kernel_entry.asm \
               $(INC_DIR)/boot.inc $(INC_DIR)/gdt.inc $(INC_DIR)/vga.inc $(INC_DIR)/serial.inc | $(BUILD_DIR)
	$(NASM) $(NASM_FLAGS) -f bin $< -o $@
	@echo "[OK] Stage 2 & Protected Mode Subsystems assembled: $$(stat -c %s $@) bytes"

# Build Demonstration C Kernel Payload
$(BUILD_DIR)/c_entry.o: $(C_ENTRY_SRC) | $(BUILD_DIR)
	$(NASM) -f elf32 $< -o $@

$(BUILD_DIR)/c_kernel.o: $(C_KERN_SRC) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(KERNEL_BIN): $(BUILD_DIR)/c_entry.o $(BUILD_DIR)/c_kernel.o $(LINKER_SCR)
	$(LD) $(LDFLAGS) -T $(LINKER_SCR) $(BUILD_DIR)/c_entry.o $(BUILD_DIR)/c_kernel.o -o $@
	@echo "[OK] Demonstration C Kernel compiled and linked: $$(stat -c %s $@) bytes"

# Construct raw bootable disk image
$(BOOT_IMG): $(STAGE1_BIN) $(STAGE2_BIN) $(KERNEL_BIN)
	@echo "[IMAGE] Packaging raw bootable disk image..."
	dd if=/dev/zero of=$@ bs=512 count=$(TOTAL_SECTORS) status=none
	dd if=$(STAGE1_BIN) of=$@ conv=notrunc bs=512 seek=0 status=none
	dd if=$(STAGE2_BIN) of=$@ conv=notrunc bs=512 seek=1 status=none
	dd if=$(KERNEL_BIN) of=$@ conv=notrunc bs=512 seek=33 status=none
	@echo "[SUCCESS] Bootable disk image created: $@ ($$(stat -c %s $@) bytes)"

# ------------------------------------------------------------------------------
# Emulation & Testing
# ------------------------------------------------------------------------------

# Launch QEMU with graphical window and serial stdio
run: $(BOOT_IMG)
	$(QEMU) -drive format=raw,file=$(BOOT_IMG),media=disk -net none -serial stdio

# Launch QEMU in curses mode (terminal UI)
run-curses: $(BOOT_IMG)
	$(QEMU) -drive format=raw,file=$(BOOT_IMG),media=disk -net none -serial stdio -display curses

# Launch QEMU headless (serial output directly in terminal)
run-headless: $(BOOT_IMG)
	$(QEMU) -drive format=raw,file=$(BOOT_IMG),media=disk -net none -serial stdio -display none

# Launch QEMU with GDB stub frozen at first instruction (0x7C00)
debug: $(BOOT_IMG)
	@echo "Starting QEMU in debug mode on localhost:1234..."
	$(QEMU) -drive format=raw,file=$(BOOT_IMG),media=disk -net none -serial stdio -s -S

# Launch GDB client to connect to QEMU debug session
gdb:
	gdb -ex "target remote localhost:1234" -ex "set architecture i8086" -ex "break *0x7C00" -ex "continue"

# Automated test suite
test: $(BOOT_IMG)
	@echo "[TEST] Running automated boot and shell verification..."
	@printf "help\ncpuinfo\nmmap\nkernel\n" | timeout 4 $(QEMU) -drive format=raw,file=$(BOOT_IMG),media=disk -net none -serial stdio -display none > $(BUILD_DIR)/test_output.log 2>&1 || true
	@grep -q "SHAE Multistage x86 Protected Mode Bootloader" $(BUILD_DIR)/test_output.log && echo "[PASS] Banner displayed"
	@grep -q "CPU Vendor ID" $(BUILD_DIR)/test_output.log && echo "[PASS] CPUID inspection working"
	@grep -q "E820 PHYSICAL MEMORY MAP" $(BUILD_DIR)/test_output.log && echo "[PASS] E820 Memory Map parsed"
	@grep -q "SHAE DEMO C KERNEL PAYLOAD BOOTED" $(BUILD_DIR)/test_output.log && echo "[PASS] C Kernel payload executed"
	@echo "[TEST] All bootloader subsystems PASSED!"

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	@echo "[CLEAN] Build directory removed."

# Help message
help:
	@echo "SHAE x86 Bootloader Build Targets:"
	@echo "  make              - Build bootable disk image (build/shae_boot.img)"
	@echo "  make run          - Run bootloader in QEMU (GUI + Serial stdio)"
	@echo "  make run-curses   - Run in terminal console (curses mode)"
	@echo "  make run-headless - Run headless with pure serial terminal output"
	@echo "  make test         - Run automated functional test suite"
	@echo "  make debug        - Start QEMU with GDB server paused at 0x7C00"
	@echo "  make gdb          - Connect GDB to running QEMU debug session"
	@echo "  make clean        - Remove build artifacts"
