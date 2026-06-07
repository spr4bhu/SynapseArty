# Program the Arty A7-35T over JTAG (volatile config, cleared on power cycle).
# Usage: vivado -mode batch -source fpga/program_arty.tcl -tclargs <bitfile>

set here [file normalize [file dirname [info script]]]
set bit  [file normalize $here/build/arty_top.bit]
if {$argc > 0} { set bit [file normalize [lindex $argv 0]] }

open_hw_manager
connect_hw_server
open_hw_target

set dev [lindex [get_hw_devices] 0]
puts "==== Target device: $dev ===="
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "==== PROGRAMMED $bit ===="
close_hw_target
disconnect_hw_server
close_hw_manager
