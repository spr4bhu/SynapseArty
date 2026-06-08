# SynapseArty

The [synapse32](https://github.com/spr4bhu/synapse32) RV32I core running on a
**Digilent Arty A7-35T**. The core executes from on-chip block RAM and integrates
the board's **256 MB DDR3** as external memory at `0x80000000` through the Xilinx
MIG — read/write verified on hardware.

## Specs

- **ISA:** RV32I + Zicsr + Zifencei, 5-stage pipeline.
- **Memory:** 32 KB instruction + 32 KB data block RAM, plus 256 MB external DDR3
  at `0x80000000`.
- **Clock:** 83.33 MHz — the design runs in the MIG `ui_clk` domain.
- **UART:** 115200 8N1 on the USB-UART bridge.
- **Boot:** from QSPI flash, or volatile over JTAG.

## Memory map

| Region      | Base         | Size   |
|-------------|--------------|--------|
| Instruction | `0x00000000` | 32 KB  |
| Data        | `0x10000000` | 32 KB  |
| Timer       | `0x02004000` | —      |
| UART        | `0x20000000` | —      |
| DDR3        | `0x80000000` | 256 MB |

UART registers: `DATA +0`, `STATUS +4`, `CONTROL +8`, `BAUD +C`.

## Board pins

| Signal         | Pin          | Use                                         |
|----------------|--------------|---------------------------------------------|
| `CLK100MHZ`    | E3           | 100 MHz clock                               |
| `ck_rst`       | C2           | reset (active-low)                          |
| `uart_rxd_out` | D10          | UART TX                                     |
| `led[0..3]`    | H5 J5 T9 T10 | calib done, heartbeat, MMCM locked, running |

DDR3 pins are constrained by the MIG IP.

## Layout

```
rtl/          core; fpga/arty_ddr3_top.v (synthesis top)
              ddr3_bridge.v bridges the CPU to the MIG native UI
constraints/  arty_a7_35t_ddr3.xdc
fpga/         build / program / flash scripts; mig/ generates the DDR3 controller
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

Generate the MIG DDR3 controller once (output is gitignored and regenerable):
```
vivado -mode batch -source fpga/mig/gen_mig.tcl
```

Synthesize, implement, and write the bitstream:
```
vivado -mode batch -source fpga/impl_ddr3.tcl -tclargs fpga/build/app.hex
```

Program over JTAG (volatile):
```
vivado -mode batch -source fpga/program_arty.tcl -tclargs fpga/build/arty_ddr3_top.bit
```

Read the UART:
```
stty -F /dev/ttyUSB1 115200 raw -echo && cat /dev/ttyUSB1
```

Write to QSPI flash (persists across power cycles):
```
vivado -mode batch -source fpga/flash_arty.tcl -tclargs fpga/build/arty_ddr3_top.bit
```

`sim/ddr3_test.c` writes patterns to DDR3 and reads them back over UART.

## Notes

- Data loads cost one extra cycle (synchronous BRAM read, absorbed by a pipeline
  stall). Instruction fetch is pipelined, so taken branches cost one cycle.
- DDR3 access stalls the pipeline for the full controller latency, so it is correct
  but slow.
- The QSPI image uses x1 boot. For x4, build with `BITSTREAM.CONFIG.SPI_BUSWIDTH 4`.

## Future work

DDR3 is currently a read/write region; the plan is to make it the main memory the
core actually runs from:

- **Move instruction and data memory into DDR3** — use the 256 MB DDR3 as unified
  main memory (text + data + stack) instead of the 32 KB BRAM.
- **Add a bootloader** in BRAM that loads the program from QSPI flash into DDR3 and
  jumps to it, so the core boots and executes entirely from DDR3.
- **Add the cache from [synapse32](https://github.com/spr4bhu/synapse32)** to hide
  DDR3 latency — the existing pipeline already exposes a stall hook the cache plugs
  into, restoring near-BRAM speed on hits.
