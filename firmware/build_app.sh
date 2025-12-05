#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

RISCV_PREFIX=riscv64-unknown-elf-

echo "=== Building Application Firmware (for UART upload) ==="

echo "[1] Compiling application..."
$RISCV_PREFIX"gcc" \
  -march=rv32i_zicsr -mabi=ilp32 -mno-relax \
  -ffreestanding -nostdlib -nostartfiles \
  -I freertos_kernel/include \
  -I freertos_port \
  -T link_app.ld \
  crt0.s \
  uart.c \
  main.c \
  mem_util.c \
  freertos_kernel/event_groups.c \
  freertos_kernel/list.c \
  freertos_kernel/queue.c \
  freertos_kernel/stream_buffer.c \
  freertos_kernel/tasks.c \
  freertos_kernel/timers.c \
  freertos_port/port.c \
  freertos_port/portASM.s \
  freertos_port/heap_4.c \
  -lgcc -o app.elf

echo "[2] ELF -> BIN..."
$RISCV_PREFIX"objcopy" -O binary app.elf app.bin

SIZE=$(stat -c%s app.bin 2>/dev/null || stat -f%z app.bin)
echo ""
echo "=== Application build complete! ==="
echo "Binary: app.bin ($SIZE bytes)"
echo ""
echo "To upload to FPGA via bootloader:"
echo "  python upload.py COM3 app.bin"
echo ""
echo "(Replace COM3 with your actual serial port)"

