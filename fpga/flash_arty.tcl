# Program the Arty A7-35T QSPI flash so the design boots on power-up (non-volatile).
# Generates an .mcs from the bitstream and writes it to the on-board Micron
# MT25QL128 (quad-SPI). The Arty A7 boots from QSPI by default, so no jumper change.
#
# Usage: vivado -mode batch -source fpga/flash_arty.tcl -tclargs <bitfile>

set here [file normalize [file dirname [info script]]]
set bit  [file normalize $here/build/arty_ddr3_top.bit]
if {$argc > 0} { set bit [file normalize [lindex $argv 0]] }
set mcs  [file rootname $bit].mcs

set part    xc7a35ticsg324-1L
set cfgmem  mt25ql128-spi-x1_x2_x4   ; # Arty A7-35T flash chip (Micron)

# Bitstream -> .mcs. SPIx1 matches the default bitstream (use SPIx4 if built with
# BITSTREAM.CONFIG.SPI_BUSWIDTH 4).
write_cfgmem -force -format mcs -size 16 -interface SPIx1 \
    -loadbit "up 0x0 $bit" -file $mcs
puts "==== MCS written: $mcs ===="

# 2) Connect to the board over JTAG.
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

# 3) Attach the QSPI flash to the device.
create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $cfgmem] 0]
set cfg [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfg
set_property PROGRAM.FILES        [list $mcs] $cfg
set_property PROGRAM.BLANK_CHECK  0 $cfg
set_property PROGRAM.ERASE        1 $cfg
set_property PROGRAM.CFG_PROGRAM  1 $cfg
set_property PROGRAM.VERIFY       1 $cfg
set_property PROGRAM.CHECKSUM     0 $cfg

# Load the indirect-programming bridge into the FPGA (required to reach the flash).
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
refresh_hw_device $dev

# 3b) Program the flash through the bridge.
program_hw_cfgmem -hw_cfgmem $cfg
puts "==== QSPI FLASH PROGRAMMED ===="

# 4) Trigger a boot from flash (acts like a power-on reconfig) to verify.
boot_hw_device $dev
puts "==== BOOTED FROM FLASH ===="

close_hw_target
disconnect_hw_server
close_hw_manager
