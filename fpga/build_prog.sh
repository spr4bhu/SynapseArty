#!/usr/bin/env bash
# Compile a bare-metal C program into a word-per-line hex for the unified memory.
#   usage:  fpga/build_prog.sh <src.c> <out.hex>
#   set RISCV_PREFIX if your toolchain isn't riscv64-unknown-elf- on PATH.
set -euo pipefail

SRC="$1"
OUT="$2"
PREFIX="${RISCV_PREFIX:-riscv64-unknown-elf-}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(dirname "$OUT")"
mkdir -p "$WORK"

# rv32i + zicsr (the cycle CSR etc.), soft-float ABI, freestanding.
"${PREFIX}gcc" -march=rv32i_zicsr -mabi=ilp32 -nostdlib -ffreestanding -O1 \
    -T "$HERE/sim/link.ld" "$HERE/sim/start.S" "$SRC" -o "$WORK/prog.elf"

# Flat binary of the code sections (objcopy starts it at the lowest section VMA).
"${PREFIX}objcopy" -O binary -j .nop_section -j .text "$WORK/prog.elf" "$WORK/prog.bin"

# Base load address = lowest code-section VMA. $readmemh places the words there;
# unified_memory NOP-fills everything below it, so the core reaches _start.
BASE=$("${PREFIX}objdump" -h "$WORK/prog.elf" \
       | awk '$2==".nop_section"||$2==".text"{print $4}' | sort | head -1)

# Pack little-endian 32-bit words, 4 per line, at the base word address.
python3 - "$WORK/prog.bin" "$OUT" "$BASE" <<'PY'
import sys, struct
data = open(sys.argv[1], 'rb').read()
base_word = int(sys.argv[3], 16) // 4
while len(data) % 4:
    data += b'\x00'
words = [struct.unpack('<I', data[i:i+4])[0] for i in range(0, len(data), 4)]
with open(sys.argv[2], 'w') as f:
    f.write(f"@{base_word:08X}\n")
    for i in range(0, len(words), 4):
        f.write(" ".join(f"{w:08X}" for w in words[i:i+4]) + "\n")
print(f"{len(words)} words @ {sys.argv[3]} -> {sys.argv[2]}")
PY
