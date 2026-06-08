## Synapse-32 on Digilent Arty A7-35T, DDR3 build (arty_ddr3_top).
## Board pins only; the DDR3 device pins are constrained by the MIG IP's own xdc.

## Configuration / bitstream
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## 100 MHz system clock (feeds the MMCM that drives the MIG)
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -name sys_clk -period 10.000 [get_ports { CLK100MHZ }]

## Reset button (active LOW) - "RESET" push button, net ck_rst
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { ck_rst }]

## UART: FPGA TX into the USB-UART bridge
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_out }]

## LEDs (LD4..LD7): [0] calib done, [1] ui_clk heartbeat, [2] MMCM locked, [3] running
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]
