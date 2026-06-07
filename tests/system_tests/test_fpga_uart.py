"""Sim gate for the FPGA bring-up program (fpga_uart_test.c).

Loads the SAME hex that will be baked into the bitstream and checks the CPU
actually transmits the "SYNAPSE32 ON ARTY OK" banner on uart_tx at the real
115200 baud (divisor 434 @ 50 MHz). This proves the program runs end-to-end
before we spend minutes on synth/place/route/bitstream.
"""
import os
import subprocess
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# Reuse the bit-banging UART monitor from the existing UART test.
from test_uart_cpu import UartMonitor

BANNER = "SYNAPSE32 ON ARTY OK"


@cocotb.test()
async def test_fpga_uart_banner(dut):
    """Run fpga_uart_test.hex and confirm the banner appears on uart_tx."""
    clock = Clock(dut.clk, 20, units="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    dut.timer_interrupt.value = 0
    dut.software_interrupt.value = 0
    dut.external_interrupt.value = 0
    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0

    # Real on-board baud: 50 MHz / 434 ~= 115200.
    uart_monitor = UartMonitor(dut.uart_tx, dut.clk, baud_rate=115200)
    cocotb.start_soon(uart_monitor.start_monitoring())

    # One banner is ~21 chars * 10 bits * 434 cyc ~= 91k cycles; give headroom.
    await ClockCycles(dut.clk, 200_000)

    received = uart_monitor.get_received_string()
    cocotb.log.info(f"UART received: {received!r}")
    assert BANNER in received, f"Expected {BANNER!r} on uart_tx, got {received!r}"


def runCocotbTests():
    from cocotb_test.simulator import run

    curr_dir = os.getcwd()
    root_dir = curr_dir
    while not os.path.exists(os.path.join(root_dir, "rtl")):
        if os.path.dirname(root_dir) == root_dir:
            raise FileNotFoundError("rtl directory not found")
        root_dir = os.path.dirname(root_dir)
    rtl_dir = os.path.join(root_dir, "rtl")
    incl_dir = os.path.join(rtl_dir, "include")

    sources = []
    for r, _, files in os.walk(rtl_dir):
        for f in files:
            if f.endswith(".v") or f.endswith(".sv"):
                sources.append(os.path.join(r, f))

    # Build the program hex from source so this passes on a fresh checkout.
    hex_file = str((Path(root_dir) / "fpga" / "build" / "fpga_uart_test.hex").absolute())
    src = str((Path(root_dir) / "sim" / "fpga_uart_test.c").absolute())
    builder = str((Path(root_dir) / "fpga" / "build_prog.sh").absolute())
    subprocess.run(["bash", builder, src, hex_file], check=True)
    sim_build_dir = os.path.join(curr_dir, "sim_build", "sim_build_fpga_uart")

    run(
        verilog_sources=sources,
        toplevel="top",
        module="test_fpga_uart",
        testcase="test_fpga_uart_banner",
        includes=[str(incl_dir)],
        simulator="verilator",
        timescale="1ns/1ps",
        defines=[f'INSTR_HEX_FILE="{hex_file}"'],
        sim_build=sim_build_dir,
        force_compile=True,
    )


if __name__ == "__main__":
    runCocotbTests()
