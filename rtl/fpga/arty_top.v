`default_nettype none

// Synthesis top for the Arty A7-35T: MMCM clock, reset sync, UART + status LEDs.
// rtl/top.v is the (untouched) simulation top. INIT_FILE bakes a program image
// into the unified memory; "" runs NOPs.

module arty_top #(
    parameter INIT_FILE = ""
) (
    input  wire        CLK100MHZ,   // E3  - 100 MHz board oscillator
    input  wire        ck_rst,      // C2  - reset button, ACTIVE LOW
    output wire        uart_rxd_out, // D10 - FPGA TX -> USB-UART bridge RX
    output wire [3:0]  led          // H5 J5 T9 T10
);

    // 100 MHz -> 62.5 MHz: VCO = 100*10 = 1000 MHz, CLKOUT0 = 1000/16 = 62.5 MHz.
    wire clk_core;
    wire clk_core_unbuf;
    wire clkfb_unbuf, clkfb;
    wire mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKIN1_PERIOD    (10.000),   // 100 MHz input
        .DIVCLK_DIVIDE    (1),
        .CLKFBOUT_MULT_F  (10.000),   // VCO = 1000 MHz
        .CLKOUT0_DIVIDE_F (16.000),   // 62.5 MHz
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE    (0.000),
        .STARTUP_WAIT     ("FALSE")
    ) mmcm_inst (
        .CLKIN1   (CLK100MHZ),
        .CLKFBIN  (clkfb),
        .CLKFBOUT (clkfb_unbuf),
        .CLKOUT0  (clk_core_unbuf),
        .CLKOUT0B (),
        .CLKOUT1  (), .CLKOUT1B (),
        .CLKOUT2  (), .CLKOUT2B (),
        .CLKOUT3  (), .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .CLKFBOUTB(),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    BUFG bufg_fb  (.I(clkfb_unbuf),  .O(clkfb));
    BUFG bufg_clk (.I(clk_core_unbuf),  .O(clk_core));

    // Reset: assert on button (active-low) or MMCM not locked; sync de-assertion.
    wire async_rst = ~ck_rst | ~mmcm_locked;
    reg [1:0] rst_sync;
    always @(posedge clk_core or posedge async_rst) begin
        if (async_rst) rst_sync <= 2'b11;
        else           rst_sync <= {rst_sync[0], 1'b0};
    end
    wire rst_core = rst_sync[1];

    wire        uart_tx;
    wire [31:0] pc_debug;
    wire [31:0] instr_debug;

    top #(
        .INIT_FILE(INIT_FILE),
        .UART_BAUD_DIV(16'd543)   // 62.5 MHz / 115200
    ) cpu_top (
        .clk               (clk_core),
        .rst               (rst_core),
        .software_interrupt(1'b0),
        .external_interrupt(1'b0),
        .uart_tx           (uart_tx),
        .pc_debug          (pc_debug),
        .instr_debug       (instr_debug)
    );

    assign uart_rxd_out = uart_tx;

    // LEDs: [0] heartbeat (~0.93 Hz), [1] UART TX, [2] PC activity, [3] reset.
    reg [25:0] heartbeat;
    always @(posedge clk_core) heartbeat <= heartbeat + 26'd1;

    assign led[0] = heartbeat[25];
    assign led[1] = uart_tx;
    assign led[2] = pc_debug[2];
    assign led[3] = rst_core;

endmodule
`default_nettype wire
