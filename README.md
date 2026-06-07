# SynapseArty

The [synapse32](https://github.com/spr4bhu/synapse32) RV32I core running on a
**Digilent Arty A7-35T**, executing from on-chip block RAM. No external DDR3.

## Specs

- **ISA:** RV32I + Zicsr + Zifencei, 5-stage pipeline.
- **Memory:** 32 KB instruction + 32 KB data, synchronous dual-port block RAM.
- **Clock:** 62.5 MHz (MMCM from the 100 MHz board oscillator).
- **UART:** 115200 8N1 on the USB-UART bridge.
- **Boot:** from QSPI flash, or volatile over JTAG.

## Memory map

| Region      | Base         | Size  |
|-------------|--------------|-------|
| Instruction | `0x00000000` | 32 KB |
| Data        | `0x10000000` | 32 KB |
| Timer       | `0x02004000` | —     |
| UART        | `0x20000000` | —     |

UART registers: `DATA +0`, `STATUS +4`, `CONTROL +8`, `BAUD +C`.

## Board pins

| Signal         | Pin | Use                         |
|----------------|-----|-----------------------------|
| `CLK100MHZ`    | E3  | 100 MHz clock               |
| `ck_rst`       | C2  | reset (active-low)          |
| `uart_rxd_out` | D10 | UART TX                     |
| `led[0..3]`    | H5 J5 T9 T10 | heartbeat, UART, PC, reset |

## Layout

```
rtl/          core + fpga/arty_top.v (synthesis top)
constraints/  arty_a7_35t.xdc
fpga/         build / program / flash scripts
sim/          startup, linker, example C programs
tests/        cocotb + Verilator suite
```

## Requirements

- Vivado 2024.2
- RISC-V GCC (`riscv64-unknown-elf-`, or set `RISCV_PREFIX`)
- For simulation: Python 3, Verilator, `tests/requirements.txt`

## Use

Simulate:
```
cd tests && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
SIM=verilator python -m pytest
```

Build a program image (C → hex):
```
fpga/build_prog.sh sim/fpga_uart_test.c fpga/build/app.hex
```

Synthesize, implement, and write the bitstream:
```
vivado -mode batch -source fpga/impl_arty.tcl -tclargs fpga/build/app.hex
```

Program over JTAG (volatile):
```
vivado -mode batch -source fpga/program_arty.tcl -tclargs fpga/build/arty_top.bit
```

Read the UART:
```
stty -F /dev/ttyUSB1 115200 raw -echo && cat /dev/ttyUSB1
```

Write to QSPI flash (persists across power cycles):
```
vivado -mode batch -source fpga/flash_arty.tcl -tclargs fpga/build/arty_top.bit
```

## Notes

- Data loads cost one extra cycle (synchronous BRAM read, absorbed by a pipeline
  stall). Instruction fetch is pipelined, so taken branches cost one cycle.
- 62.5 MHz is near the timing limit for this design; going higher needs deeper
  pipelining.
- The QSPI image uses x1 boot. For x4, build with `BITSTREAM.CONFIG.SPI_BUSWIDTH 4`.
