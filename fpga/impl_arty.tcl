# Full implementation (synth -> place -> route -> bitstream) for Synapse-32 on
# Arty A7-35T, with the program image baked into on-chip memory via INIT_FILE.
#
# Usage:
#   vivado -mode batch -source fpga/impl_arty.tcl -tclargs <init_hex_file>

set part   xc7a35ticsg324-1L
set here   [file normalize [file dirname [info script]]]
set rtl    [file normalize $here/../rtl]
set constr [file normalize $here/../constraints/arty_a7_35t.xdc]
set outdir [file normalize $here/build]
file mkdir $outdir

set init_file ""
if {$argc > 0} { set init_file [file normalize [lindex $argv 0]] }

set sources [list \
    $rtl/fpga/arty_top.v \
    $rtl/top.v \
    $rtl/unified_memory.v \
    $rtl/memory_unit.v \
    $rtl/writeback.v \
    $rtl/riscv_cpu.v \
    $rtl/execution_unit.v \
    $rtl/pipeline_stages/IF_ID.v \
    $rtl/pipeline_stages/MEM_WB.v \
    $rtl/pipeline_stages/EX_MEM.v \
    $rtl/pipeline_stages/store_load_detector.v \
    $rtl/pipeline_stages/ID_EX.v \
    $rtl/pipeline_stages/load_use_detector.v \
    $rtl/pipeline_stages/forwarding_unit.v \
    $rtl/pipeline_stages/store_load_forward.v \
    $rtl/core_modules/csr_exec.v \
    $rtl/core_modules/alu.v \
    $rtl/core_modules/csr_file.v \
    $rtl/core_modules/timer.v \
    $rtl/core_modules/registerfile.v \
    $rtl/core_modules/uart.v \
    $rtl/core_modules/interrupt_controller.v \
    $rtl/core_modules/pc.v \
    $rtl/core_modules/decoder.v \
]

read_verilog $sources
read_xdc $constr
set_property include_dirs [list $rtl/include] [current_fileset]

if {$init_file ne ""} {
    puts "==== INIT_FILE = $init_file ===="
    set_property generic "INIT_FILE=\"$init_file\"" [current_fileset]
}

synth_design -top arty_top -part $part -include_dirs $rtl/include
write_checkpoint -force $outdir/arty_top_synth.dcp

opt_design
place_design
phys_opt_design
route_design

write_checkpoint   -force $outdir/arty_top_routed.dcp
report_utilization        -file $outdir/utilization_impl.rpt
report_timing_summary     -file $outdir/timing_summary_impl.rpt

write_bitstream -force $outdir/arty_top.bit
puts "==== BITSTREAM WRITTEN: $outdir/arty_top.bit ===="
