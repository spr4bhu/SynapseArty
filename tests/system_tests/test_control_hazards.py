"""Control-hazard (branch squash) test on the REAL memory (toplevel `top`).

Replaces the old bare-core version that drove instructions from a Python memory
mock: with synchronous fetch (registered instruction read), faithfully modelling
memory timing in Python during branch redirects is fragile. Running the same
program against the actual unified_memory is both simpler and authoritative.

Program: set x3=1, then a TAKEN beq that must skip two `addi x3,x3,1` and land on
`addi x3,x3,-1`. Correct branch squashing => x3 == 0.
"""
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

PROGRAM = [
    0x00a00093,  # addi x1,x0,10
    0x00500113,  # addi x2,x0,5
    0x00208463,  # beq  x1,x2,+8     (not taken: 10 != 5)
    0x00000013,  # nop
    0x00100193,  # addi x3,x0,1      -> x3 = 1
    0x00a00093,  # addi x1,x0,10
    0x00a00113,  # addi x2,x0,10
    0x00208663,  # beq  x1,x2,+12    (taken: skip the next two, land on the -1)
    0x00118193,  # addi x3,x3,1      (squashed)
    0x00118193,  # addi x3,x3,1      (squashed)
    0xfff18193,  # addi x3,x3,-1     -> x3 = 0
]


def _write_hex(path):
    words = list(PROGRAM)
    while len(words) < 64:
        words.append(0x00000013)  # NOP fill
    with open(path, "w") as f:
        f.write("@00000000\n")
        for i in range(0, len(words), 4):
            f.write(" ".join(f"{w:08X}" for w in words[i:i + 4]) + "\n")


@cocotb.test()
async def test_control_hazards(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    dut.timer_interrupt.value = 0
    dut.software_interrupt.value = 0
    dut.external_interrupt.value = 0
    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 40)

    x1 = int(dut.cpu_inst.rf_inst0.register_file[1].value)
    x2 = int(dut.cpu_inst.rf_inst0.register_file[2].value)
    x3 = int(dut.cpu_inst.rf_inst0.register_file[3].value)
    cocotb.log.info(f"control-hazard result: x1={x1:#x} x2={x2:#x} x3={x3:#x}")
    assert x1 == 0xa, f"x1={x1:#x} expected 0xa"
    assert x2 == 0xa, f"x2={x2:#x} expected 0xa"
    assert x3 == 0x0, f"x3={x3:#x} expected 0x0 (taken branch must squash the two +1s)"


def runCocotbTests():
    from cocotb_test.simulator import run
    root = os.getcwd()
    while not os.path.exists(os.path.join(root, "rtl")):
        root = os.path.dirname(root)
    rtl = os.path.join(root, "rtl")
    srcs = [os.path.join(r, f) for r, _, fs in os.walk(rtl)
            for f in fs if f.endswith((".v", ".sv"))]
    build = os.path.join(root, "tests", "build")
    os.makedirs(build, exist_ok=True)
    hexf = os.path.join(build, "control_hazards.hex")
    _write_hex(hexf)
    run(verilog_sources=srcs, toplevel="top", module="test_control_hazards",
        testcase="test_control_hazards", includes=[os.path.join(rtl, "include")],
        simulator="verilator", timescale="1ns/1ps",
        defines=[f'INSTR_HEX_FILE="{hexf}"'],
        sim_build=os.path.join(os.getcwd(), "sim_build", "sim_build_ctrlhaz"),
        force_compile=True)


if __name__ == "__main__":
    runCocotbTests()
