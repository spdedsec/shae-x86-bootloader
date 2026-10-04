#!/usr/bin/env bash
# ==============================================================================
# SHAE x86 Bootloader - QEMU Run & Emulation Helper Script
# ==============================================================================

set -euo pipefail

IMAGE="build/shae_boot.img"
QEMU="${QEMU:-qemu-system-x86_64}"

if [ ! -f "$IMAGE" ]; then
    echo "Disk image '$IMAGE' not found! Building project first..."
    make
fi

MODE="${1:-gui}"

case "$MODE" in
    gui)
        echo "[RUN] Launching QEMU with Graphical Window and Serial stdio..."
        "$QEMU" -drive format=raw,file="$IMAGE",media=disk -net none -serial stdio
        ;;
    headless|cli)
        echo "[RUN] Launching QEMU in Headless Serial Console mode..."
        "$QEMU" -drive format=raw,file="$IMAGE",media=disk -net none -serial stdio -display none
        ;;
    curses)
        echo "[RUN] Launching QEMU in Curses Terminal mode..."
        "$QEMU" -drive format=raw,file="$IMAGE",media=disk -net none -serial stdio -display curses
        ;;
    debug)
        echo "[DEBUG] Starting QEMU paused at 0x7C00 with GDB server on :1234..."
        "$QEMU" -drive format=raw,file="$IMAGE",media=disk -net none -serial stdio -s -S
        ;;
    test)
        echo "[TEST] Running automated boot and shell self-test..."
        printf "help\ncpuinfo\nmmap\nkernel\n" | timeout 4 "$QEMU" -drive format=raw,file="$IMAGE",media=disk -net none -serial stdio -display none
        ;;
    *)
        echo "Usage: $0 [gui|headless|curses|debug|test]"
        exit 1
        ;;
esac
