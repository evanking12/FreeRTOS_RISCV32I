#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

RISCV_PREFIX=riscv64-unknown-elf-

echo "[1] Building FreeRTOS firmware -> prog.elf..."

# Compile assembly file with preprocessor (uppercase .S)
$RISCV_PREFIX"gcc" \
  -march=rv32i_zicsr -mabi=ilp32 -mno-relax \
  -ffreestanding -nostdlib -nostartfiles \
  -I freertos_kernel/include \
  -I freertos_port \
  -T link.ld \
  crt0.s \
  uart.c \
  main.c \
  mem_util.c \
  \
  freertos_kernel/event_groups.c \
  freertos_kernel/list.c \
  freertos_kernel/queue.c \
  freertos_kernel/stream_buffer.c \
  freertos_kernel/tasks.c \
  freertos_kernel/timers.c \
  \
  freertos_port/port.c \
  freertos_port/portASM.S \
  freertos_port/heap_4.c \
  \
  -lgcc -o prog.elf

echo "[2] ELF -> BIN..."
$RISCV_PREFIX"objcopy" -O binary prog.elf prog.bin

echo "[3] BIN -> HEX..."
xxd -p -c 4 prog.bin > prog.hex

echo "[4] HEX -> instr_mem.vh..."
python3 make_hex.py

echo "[5] Copying instr_mem.vh to Vivado directories..."
# Copy to all locations Vivado might look for the file
cp instr_mem.vh ../instr_mem.vh
cp instr_mem.vh ../FPGA_CPU1.runs/synth_1/instr_mem.vh 2>/dev/null || true
cp instr_mem.vh ../FPGA_CPU1.ip_user_files/mem_init_files/instr_mem.vh 2>/dev/null || true
cp instr_mem.vh ../FPGA_CPU1.sim/sim_1/behav/xsim/instr_mem.vh 2>/dev/null || true
cp instr_mem.vh ../sim_debug/instr_mem.vh 2>/dev/null || true

echo "✅ FreeRTOS firmware build complete!"
echo ""
echo "IMPORTANT: In Vivado, you must:"
echo "  1. Run 'Reset Synthesis' (right-click on synthesis)"
echo "  2. Then re-run Synthesis -> Implementation -> Generate Bitstream"
echo "  3. Or use 'Update Memory Configuration' if available"
