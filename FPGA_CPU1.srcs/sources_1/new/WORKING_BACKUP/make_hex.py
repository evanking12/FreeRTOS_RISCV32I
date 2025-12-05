#!/usr/bin/env python3
from pathlib import Path

BIN_PATH = Path("prog.bin")
VH_PATH = Path("instr_mem.vh")
WORD_COUNT = 32768  # 128 KB / 4 bytes

def main():
    if not BIN_PATH.exists():
        print(f"ERROR: {BIN_PATH} not found!")
        return

    data = BIN_PATH.read_bytes()
    bin_size = len(data)
    print(f"Binary size: {bin_size} bytes")

    max_size = WORD_COUNT * 4
    if bin_size > max_size:
        print(f"ERROR: Binary too large ({bin_size} bytes > {max_size})")
        return

    padded = data.ljust(max_size, b"\x00")

    lines = []
    for i in range(WORD_COUNT):
        word_bytes = padded[4 * i:4 * i + 4]
        word = int.from_bytes(word_bytes, "little")
        lines.append(f"{word:08x}")

    VH_PATH.write_text("\n".join(lines) + "\n")
    print(f"Wrote {VH_PATH} with {WORD_COUNT} words (plain hex).")

if __name__ == "__main__":
    main()
