#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

RISCV_PREFIX=riscv64-unknown-elf-

echo "=== Building UART Bootloader ==="

echo "[1] Compiling bootloader..."
${RISCV_PREFIX}gcc \
  -march=rv32i -mabi=ilp32 -mno-relax \
  -ffreestanding -nostdlib -nostartfiles \
  -T boot_link.ld \
  boot.s \
  -o boot.elf

echo "[2] ELF -> BIN..."
${RISCV_PREFIX}objcopy -O binary boot.elf boot.bin

echo "[3] Generating boot_mem.vh..."
# Generate hex file for Vivado
python3 << 'EOF'
from pathlib import Path

data = Path("boot.bin").read_bytes()
print(f"Bootloader size: {len(data)} bytes")

# Pad to 32KB (full memory space, app will go at 0x1000)
TOTAL_WORDS = 32768  # 128KB / 4
padded = data.ljust(TOTAL_WORDS * 4, b"\x00")

lines = []
for i in range(TOTAL_WORDS):
    word = int.from_bytes(padded[4*i:4*i+4], "little")
    lines.append(f"{word:08x}")

Path("boot_mem.vh").write_text("\n".join(lines) + "\n")
print(f"Wrote boot_mem.vh")
EOF

echo "[4] Copying to parent directories..."
cp boot_mem.vh ../instr_mem.vh
cp boot_mem.vh ../../instr_mem.vh
cp boot_mem.vh ../../FPGA_CPU1.srcs/sources_1/new/ 2>/dev/null || true
cp boot_mem.vh ../../FPGA_CPU1.runs/synth_1/instr_mem.vh 2>/dev/null || true

echo ""
echo "=== Bootloader build complete! ==="
echo "Now run Vivado synthesis to bake bootloader into bitstream."
echo "After programming FPGA, use upload.py to send firmware via UART."

