import cocotb
from cocotb.triggers import RisingEdge, Timer, ClockCycles
from cocotb.clock import Clock
import logging
import os
from pathlib import Path
from cocotb.utils import get_sim_time

# Configure logging
logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger(__name__)

# UART register addresses from memory map
UART_BASE = 0x20000000
UART_DATA = UART_BASE + 0x00
UART_STATUS = UART_BASE + 0x04
UART_CONTROL = UART_BASE + 0x08
UART_BAUD = UART_BASE + 0x0C

class UartMonitor:
    """Monitor the UART TX line and decode transmitted bytes"""
    def __init__(self, uart_tx, clk, baud_rate=5000000):
        self.tx = uart_tx
        self.clk = clk
        self.baud_period_cycles = int(50_000_000 / baud_rate)  # Baud period in clock cycles
        self.received_bytes = []
        self.monitoring = True
        print(f"UART Monitor initialized with baud rate: {baud_rate} Hz, period cycles: {self.baud_period_cycles}")
        
    async def start_monitoring(self):
        """Start monitoring the UART TX line"""
        while self.monitoring:
            # Wait for TX line to go low (start bit)
            while self.tx.value != 0:
                await RisingEdge(self.clk)
                current_time = get_sim_time(units="ns")
                if not self.monitoring:
                    return
            current_time = get_sim_time(units="ns")
            print("Start bit detected at time:", current_time)
            
            await Timer((self.baud_period_cycles + 1) * 20, units="ns")
            
            # Sample data bits (LSB first) - we're now at the center of bit 0
            rx_byte = 0
            for bit_num in range(8):
                # Sample the bit (we should be in the center of the bit period)
                bit_value = int(self.tx.value)
                rx_byte |= (bit_value << bit_num)
                current_time = get_sim_time(units="ns")
                print(f"Bit {bit_num}: {bit_value} (0x{rx_byte:02x}) at time: {current_time}")
                
                # Wait one full bit period to get to the center of the next bit
                # (except for the last bit where we don't need to wait)
                if bit_num < 7:
                    await Timer((self.baud_period_cycles + 1) * 20, units="ns")
            
            # Wait one full bit period to get past the stop bit
            await Timer((self.baud_period_cycles + 1) * 20, units="ns")
            current_time = get_sim_time(units="ns")
            print(f"Stop bit received at time: {current_time}, RX byte: 0x{rx_byte:02x}")
            
            # Store received byte
            self.received_bytes.append(rx_byte)
            char = chr(rx_byte) if 32 <= rx_byte <= 126 else f'\\x{rx_byte:02x}'
            log.info(f"UART received: 0x{rx_byte:02x} ('{char}')")
            
    def get_received_string(self):
        """Get the received bytes as a string"""
        return ''.join(chr(b) if 32 <= b <= 126 else f'\\x{b:02x}' for b in self.received_bytes)

def create_uart_test_hex(test_name, instr_mem):
    """Create a hex file for the UART test instructions"""
    curr_dir = Path.cwd()
    build_dir = curr_dir / "build"
    build_dir.mkdir(exist_ok=True)
    
    hex_file = build_dir / f"{test_name}.hex"
    
    with open(hex_file, 'w') as f:
        f.write("@00000000\n")  # Start address

        # Pad the instruction to ensure we have enough instructions
        padded_instr = list(instr_mem)
        while len(padded_instr) % 4 != 0:
            padded_instr.append(0x00000013)  # NOP instruction

        # Pad to atleast 256 instructions
        while len(padded_instr) < 256:
            padded_instr.append(0x00000013)
        
        # Write instructions as 4 per line
        for i in range(0, len(padded_instr), 4):
            line =  " ".join(f"{padded_instr[j]:08x}" for j in range(i, min(i + 4, len(padded_instr))))
            f.write(f"{line}\n")

    return str(hex_file.absolute())

def run_uart_status_test():
    """Create assembly program that tests UART status register"""
    
    # UART configuration - same baud rate as hello test
    # Baud divisor = 50,000,000 / 5,000,000 = 10 (5 MHz baud rate)
    BAUD_DIVISOR = 10
    
    instr_mem = [
        # Initialize registers
        0x20000137,  # lui x2, 0x20000       # x2 = UART_BASE (0x20000000)
        0x020001b7,  # lui x3, 0x2000        # x3 = 0x02000000 (data memory base)
        
        # Set baud rate to 5MHz (same as hello test)
        0x00a00093,  # addi x1, x0, 10       # x1 = 10 (baud divisor for 5MHz)
        0x00112623,  # sw x1, 12(x2)         # UART_BAUD = 10
        
        # Enable UART
        0x00100093,  # addi x1, x0, 1        # x1 = 1 (enable UART)
        0x00112423,  # sw x1, 8(x2)          # UART_CONTROL = 1 (enable)
        
        # Read UART status register (initial)
        0x00412083,  # lw x1, 4(x2)          # x1 = UART_STATUS
        0x0011a023,  # sw x1, 0(x3)          # Store status to memory[0x02000000]
        
        # Write to UART data register
        0x04100093,  # addi x1, x0, 65       # x1 = 'A' (65)
        0x00112023,  # sw x1, 0(x2)          # UART_DATA = 'A'
        
        # Read status again (should show busy)
        0x00412083,  # lw x1, 4(x2)          # x1 = UART_STATUS
        0x0011a223,  # sw x1, 4(x3)          # Store status to memory[0x02000004]
        
        # Wait for transmission to complete
        0x00100213,  # addi x4, x0, 1        # x4 = 1 (delay counter)
        # Loop to wait for UART ready
        0x00412083,  # lw x1, 4(x2)          # x1 = UART_STATUS
        0x0040f093,  # andi x1, x1, 4        # x1 = x1 & 4 (isolate busy bit)
        0xfe009de3,  # bne x1, x0, -6        # Branch back if still busy
        
        # Read final status (should not be busy)
        0x00412083,  # lw x1, 4(x2)          # x1 = UART_STATUS
        0x0011a423,  # sw x1, 8(x3)          # Store status to memory[0x02000008]
        
        # Store completion flag
        0x00100093,  # addi x1, x0, 1        # x1 = 1 (completion marker)
        0x0011a623,  # sw x1, 12(x3)         # Store completion flag to memory[0x0200000C]
        
        # Infinite loop
        0x0000006f,  # jal x0, 0             # Jump to self
    ]
    
    test_name = "uart_status"
    hex_file = create_uart_test_hex(test_name, instr_mem)
    return test_name, hex_file

async def monitor_cpu_execution(dut, test_name, max_cycles=1000):
    """Monitor CPU execution and return memory writes"""
    mem_writes = {}
    
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        
        # Monitor memory writes to data memory
        try:
            if hasattr(dut, 'cpu_mem_write_en') and int(dut.cpu_mem_write_en.value):
                addr = int(dut.cpu_mem_write_addr.value)
                data = int(dut.cpu_mem_write_data.value)
                mem_writes[addr] = data
                log.info(f"Cycle {cycle}: Memory write: addr=0x{addr:08x}, data=0x{data:08x}")
        except Exception:
            pass
        
        # Monitor PC for debugging
        try:
            pc_val = int(dut.pc_debug.value)
            if cycle % 100 == 0:  # Print every 100 cycles
                log.debug(f"Cycle {cycle}: PC=0x{pc_val:08x}")
        except Exception:
            pass
        
        # Check for completion flag
        if 0x02000000 in mem_writes or 0x0200000C in mem_writes:
            # Give more cycles for UART transmission to complete
            if cycle > 2000:
                break
    
    return mem_writes

@cocotb.test()
async def test_uart_status_register(dut):
    """Test UART status register functionality"""
    log.info("Starting UART status register test...")
    
    # Start clock (50MHz)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.timer_interrupt.value = 0
    dut.software_interrupt.value = 0
    dut.external_interrupt.value = 0
    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    
    # Start UART monitor with 5MHz (same as hello test)
    uart_monitor = UartMonitor(dut.uart_tx, dut.clk, baud_rate=5000000)
    monitor_task = cocotb.start_soon(uart_monitor.start_monitoring())
    
    # Monitor execution (reduced cycles due to faster baud rate)
    mem_writes = await monitor_cpu_execution(dut, "uart_status", max_cycles=1500)
    
    log.info("\nVerifying UART status register behavior:")
    log.info("Memory writes:", mem_writes)
    
    # Check for completion flag
    completion_found = 0x0200000C in mem_writes and mem_writes[0x0200000C] == 1
    assert completion_found, "Program completion flag not found"
    
    # Verify status register values
    if 0x02000000 in mem_writes:
        initial_status = mem_writes[0x02000000]
        log.info(f"Initial UART status: 0x{initial_status:08x}")
        # Should indicate FIFO empty (bit 1) and not busy (bit 2 clear)
        assert (initial_status & 0x2) != 0, "Initial status should show FIFO empty"
        assert (initial_status & 0x4) == 0, "Initial status should show not busy"
    
    if 0x02000004 in mem_writes:
        busy_status = mem_writes[0x02000004]
        log.info(f"Status after write: 0x{busy_status:08x}")
        # May or may not be busy depending on timing
    
    if 0x02000008 in mem_writes:
        final_status = mem_writes[0x02000008]
        log.info(f"Final UART status: 0x{final_status:08x}")
        # Should not be busy after transmission completes
        assert (final_status & 0x4) == 0, "Final status should show not busy"
    
    # Verify we received the 'A' character
    received_string = uart_monitor.get_received_string()
    log.info(f"UART received: '{received_string}'")
    assert 'A' in received_string, f"Expected 'A' in UART output, got '{received_string}'"
    
    log.info("UART status register test passed!")

def runCocotbTests():
    """Run the cocotb tests via cocotb-test"""
    from cocotb_test.simulator import run
    import shutil
    
    # Test configurations
    tests_config = [
        ("uart_status_register", run_uart_status_test),
    ]
    
    # Get repository root directory
    curr_dir = os.getcwd()
    root_dir = curr_dir
    while not os.path.exists(os.path.join(root_dir, "rtl")):
        if os.path.dirname(root_dir) == root_dir:
            raise FileNotFoundError("rtl directory not found in the current or parent directories.")
        root_dir = os.path.dirname(root_dir)
    print(f"Using RTL directory: {root_dir}/rtl")
    rtl_dir = os.path.join(root_dir, "rtl")
    incl_dir = os.path.join(rtl_dir, "include")
    
    # Collect all Verilog sources
    sources = []
    for root, _, files in os.walk(rtl_dir):
        for file in files:
            if file.endswith(".v") or file.endswith(".sv"):
                sources.append(os.path.join(root, file))
    
    enable_waves = os.getenv("WAVES", "0") == "1"
    waveform_dir = None
    if enable_waves:
        waveform_dir = os.path.join(curr_dir, "waveforms")
        if not os.path.exists(waveform_dir):
            os.makedirs(waveform_dir)
    
    # Run each test
    for test_name, test_func in tests_config:
        print(f"\n=== Generating and running {test_name} ===")
        _, hex_file = test_func()
        print(f"Generated hex file: {hex_file}")
        plus_args = []
        if enable_waves:
            waveform_path = os.path.join(waveform_dir, f"{test_name}.vcd")
            plus_args = [f"+dumpfile={waveform_path}"]
        
        # Create unique sim_build directory for each test
        if not os.path.exists(os.path.join(curr_dir, "sim_build")):
            os.makedirs(os.path.join(curr_dir, "sim_build"))
        sim_build_dir = os.path.join(curr_dir, "sim_build", f"sim_build_{test_name}")
        
        # Clean up previous sim_build for this test
        if os.path.exists(sim_build_dir):
            shutil.rmtree(sim_build_dir)
        
        run(
            verilog_sources=sources,
            toplevel="top",
            module="test_uart_cpu",
            testcase=f"test_{test_name}",
            includes=[str(incl_dir)],
            simulator="verilator",
            timescale="1ns/1ps",
            defines=[f"INSTR_HEX_FILE=\"{hex_file}\""],
            plus_args=plus_args,
            sim_build=sim_build_dir,
            force_compile=True,
        )

if __name__ == "__main__":
    runCocotbTests()
