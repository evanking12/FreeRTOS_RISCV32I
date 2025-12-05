#!/usr/bin/env bash
#
# BUILD DEBUG TESTS
# Usage:
#   ./build_debug.sh trap_test       - Build standalone trap test
#   ./build_debug.sh context_test    - Build context switch test  
#   ./build_debug.sh freertos        - Build FreeRTOS (normal)
#
set -e
cd "$(dirname "$0")"

RISCV_PREFIX=riscv64-unknown-elf-

# Default to trap_test
TEST="${1:-trap_test}"

echo "================================================"
echo "  Building: $TEST"
echo "================================================"

case "$TEST" in
    trap_test)
        MAIN_FILE="main_trap_test.c"
        EXTRA_FILES=""
        echo "Standalone trap handler test (no FreeRTOS)"
        ;;
    context_test)
        MAIN_FILE="main_context_test.c"
        EXTRA_FILES=""
        echo "Manual context switch test (no FreeRTOS)"
        ;;
    timer_test)
        MAIN_FILE="main_timer_test.c"
        EXTRA_FILES=""
        echo "Timer interrupt stress test (no FreeRTOS)"
        ;;
    freertos)
        MAIN_FILE="main.c"
        EXTRA_FILES="
            freertos_kernel/event_groups.c
            freertos_kernel/list.c
            freertos_kernel/queue.c
            freertos_kernel/stream_buffer.c
            freertos_kernel/tasks.c
            freertos_kernel/timers.c
            freertos_port/port.c
            freertos_port/portASM.S
            freertos_port/heap_4.c
        "
        echo "Full FreeRTOS build"
        ;;
    *)
        echo "Unknown test: $TEST"
        echo "Usage: $0 [trap_test|timer_test|context_test|freertos]"
        exit 1
        ;;
esac

echo ""
echo "[1] Compiling $MAIN_FILE -> prog.elf..."

$RISCV_PREFIX"gcc" \
  -march=rv32i_zicsr -mabi=ilp32 -mno-relax \
  -ffreestanding -nostdlib -nostartfiles \
  -I freertos_kernel/include \
  -I freertos_port \
  -O2 \
  -T link.ld \
  crt0.s \
  uart.c \
  $MAIN_FILE \
  mem_util.c \
  $EXTRA_FILES \
  -lgcc -o prog.elf

echo "[2] ELF -> BIN..."
$RISCV_PREFIX"objcopy" -O binary prog.elf prog.bin

echo "[3] BIN -> HEX..."
xxd -p -c 4 prog.bin > prog.hex

echo "[4] HEX -> instr_mem.vh..."
python3 make_hex.py

echo "[5] Copying instr_mem.vh to simulation directories..."
cp instr_mem.vh ../instr_mem.vh
cp instr_mem.vh ../FPGA_CPU1.runs/synth_1/instr_mem.vh 2>/dev/null || true
cp instr_mem.vh ../FPGA_CPU1.sim/sim_1/behav/xsim/instr_mem.vh 2>/dev/null || true
cp instr_mem.vh ../sim_debug/instr_mem.vh 2>/dev/null || true

# Print size info
echo ""
echo "[6] Binary size:"
ls -la prog.bin
SIZE=$($RISCV_PREFIX"size" prog.elf)
echo "$SIZE"

echo ""
echo "================================================"
echo "  Build complete: $TEST"
echo "================================================"
echo ""
echo "To run simulation:"
echo "  cd ../sim_debug"
echo "  xsim tb_cpu_behav -t tb_cpu_fast.tcl"
echo ""

