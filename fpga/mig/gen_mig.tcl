# Generate the DDR3 MIG 7-series IP for the Arty A7-35T (native UI interface).
# Params come from arty_a7_ddr3.prj (DDR3 part MT41K128M16, full pinout, etc.).
#   usage: vivado -mode batch -source fpga/mig/gen_mig.tcl

set part   xc7a35ticsg324-1L
set here   [file normalize [file dirname [info script]]]
set prj    $here/arty_a7_ddr3.prj
set outdir $here/gen
file mkdir $outdir

create_project -in_memory -part $part

create_ip -name mig_7series -vendor xilinx.com -library ip \
    -module_name ddr3_mig -dir $outdir

set_property -dict [list CONFIG.XML_INPUT_FILE $prj] [get_ips ddr3_mig]

generate_target {all} [get_ips ddr3_mig]
puts "==== MIG generated at $outdir/ddr3_mig ===="

# Show the generated top module port list for wiring the bridge/top.
set verdir $outdir/ddr3_mig
puts "==== generated files ===="
foreach f [glob -nocomplain $verdir/*.v $verdir/*.veo] { puts "  $f" }
