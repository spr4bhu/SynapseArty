`default_nettype none

// Synthesis top for the Arty A7-35T with external DDR3 (MIG 7-series, native UI).
// Milestone 1: the program (baked into BRAM via INIT_FILE) runs as usual, but a
// DDR3-mapped window (0x80000000) is served by ddr3_bridge -> MIG. The whole core
// runs in the MIG ui_clk domain (~83.33 MHz), so no clock-domain crossing.
//
// Clocking: 100 MHz board -> MMCM -> 166.666 MHz (MIG sys clk) + 200 MHz (MIG ref
// clk). MIG produces ui_clk (mem_clk/4 = 83.33 MHz) and init_calib_complete.

module arty_ddr3_top #(
    parameter INIT_FILE = ""
) (
    input  wire        CLK100MHZ,    // E3  - 100 MHz board oscillator
    input  wire        ck_rst,       // C2  - reset button, ACTIVE LOW
    output wire        uart_rxd_out,  // D10 - FPGA TX -> USB-UART bridge RX
    output wire [3:0]  led,           // H5 J5 T9 T10

    // DDR3 device pins (constrained by the MIG IP's own xdc)
    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_cas_n,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_cke,
    output wire        ddr3_ras_n,
    output wire        ddr3_reset_n,
    output wire        ddr3_we_n,
    inout  wire [15:0] ddr3_dq,
    inout  wire [1:0]  ddr3_dqs_n,
    inout  wire [1:0]  ddr3_dqs_p,
    output wire [0:0]  ddr3_cs_n,
    output wire [1:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt
);
    // ---- 100 MHz -> 166.666 MHz (sys) + 200 MHz (ref); VCO = 100*10 = 1000 MHz.
    wire sys_clk_unbuf, ref_clk_unbuf, sys_clk_i, clk_ref_i;
    wire clkfb_unbuf, clkfb, mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKIN1_PERIOD    (10.000),
        .DIVCLK_DIVIDE    (1),
        .CLKFBOUT_MULT_F  (10.000),   // VCO = 1000 MHz
        .CLKOUT0_DIVIDE_F (6.000),    // 166.666 MHz - MIG system clock
        .CLKOUT1_DIVIDE   (5),        // 200.000 MHz - MIG reference clock
        .STARTUP_WAIT     ("FALSE")
    ) mmcm_inst (
        .CLKIN1   (CLK100MHZ),
        .CLKFBIN  (clkfb),
        .CLKFBOUT (clkfb_unbuf),
        .CLKOUT0  (sys_clk_unbuf),
        .CLKOUT1  (ref_clk_unbuf),
        .CLKOUT0B (), .CLKOUT1B (),
        .CLKOUT2  (), .CLKOUT2B (),
        .CLKOUT3  (), .CLKOUT3B (),
        .CLKOUT4  (), .CLKOUT5 (), .CLKOUT6 (),
        .CLKFBOUTB(),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );
    BUFG bufg_fb  (.I(clkfb_unbuf),   .O(clkfb));
    BUFG bufg_sys (.I(sys_clk_unbuf), .O(sys_clk_i));
    BUFG bufg_ref (.I(ref_clk_unbuf), .O(clk_ref_i));

    // MIG system reset is ACTIVE LOW: run once the MMCM is locked and button released.
    wire sys_rst_n = ck_rst & mmcm_locked;

    // ---- MIG application interface (ui_clk domain) ----
    wire        ui_clk, ui_clk_sync_rst, init_calib_complete;
    wire [27:0] app_addr;
    wire [2:0]  app_cmd;
    wire        app_en, app_rdy, app_wdf_rdy;
    wire [127:0] app_wdf_data, app_rd_data;
    wire [15:0] app_wdf_mask;
    wire        app_wdf_wren, app_wdf_end, app_rd_data_valid, app_rd_data_end;

    ddr3_mig u_ddr3_mig (
        .ddr3_addr        (ddr3_addr),
        .ddr3_ba          (ddr3_ba),
        .ddr3_cas_n       (ddr3_cas_n),
        .ddr3_ck_n        (ddr3_ck_n),
        .ddr3_ck_p        (ddr3_ck_p),
        .ddr3_cke         (ddr3_cke),
        .ddr3_ras_n       (ddr3_ras_n),
        .ddr3_reset_n     (ddr3_reset_n),
        .ddr3_we_n        (ddr3_we_n),
        .ddr3_dq          (ddr3_dq),
        .ddr3_dqs_n       (ddr3_dqs_n),
        .ddr3_dqs_p       (ddr3_dqs_p),
        .ddr3_cs_n        (ddr3_cs_n),
        .ddr3_dm          (ddr3_dm),
        .ddr3_odt         (ddr3_odt),
        .init_calib_complete(init_calib_complete),
        .app_addr         (app_addr),
        .app_cmd          (app_cmd),
        .app_en           (app_en),
        .app_wdf_data     (app_wdf_data),
        .app_wdf_end      (app_wdf_end),
        .app_wdf_wren     (app_wdf_wren),
        .app_rd_data      (app_rd_data),
        .app_rd_data_end  (app_rd_data_end),
        .app_rd_data_valid(app_rd_data_valid),
        .app_rdy          (app_rdy),
        .app_wdf_rdy      (app_wdf_rdy),
        .app_sr_req       (1'b0),
        .app_ref_req      (1'b0),
        .app_zq_req       (1'b0),
        .app_sr_active    (),
        .app_ref_ack      (),
        .app_zq_ack       (),
        .ui_clk           (ui_clk),
        .ui_clk_sync_rst  (ui_clk_sync_rst),
        .app_wdf_mask     (app_wdf_mask),
        .sys_clk_i        (sys_clk_i),
        .clk_ref_i        (clk_ref_i),
        .sys_rst          (sys_rst_n)
    );

    // Core/bridge reset: held until ui_clk is up; release after calibration so the
    // program never sees the DDR3 region before it is ready.
    wire rst_core = ui_clk_sync_rst | ~init_calib_complete;

    // ---- DDR3 bridge (ui_clk domain) ----
    wire        ddr3_req, ddr3_we, ddr3_stall;
    wire [27:0] ddr3_addr_off;
    wire [31:0] ddr3_wdata, ddr3_rdata;
    wire [3:0]  ddr3_byte_enable;

    ddr3_bridge bridge (
        .clk                 (ui_clk),
        .rst                 (ui_clk_sync_rst),
        .init_calib_complete (init_calib_complete),
        .req                 (ddr3_req),
        .we                  (ddr3_we),
        .addr                (ddr3_addr_off),
        .wdata               (ddr3_wdata),
        .byte_enable         (ddr3_byte_enable),
        .rdata               (ddr3_rdata),
        .stall               (ddr3_stall),
        .app_addr            (app_addr),
        .app_cmd             (app_cmd),
        .app_en              (app_en),
        .app_wdf_data        (app_wdf_data),
        .app_wdf_mask        (app_wdf_mask),
        .app_wdf_wren        (app_wdf_wren),
        .app_wdf_end         (app_wdf_end),
        .app_rdy             (app_rdy),
        .app_wdf_rdy         (app_wdf_rdy),
        .app_rd_data         (app_rd_data),
        .app_rd_data_valid   (app_rd_data_valid)
    );

    // ---- CPU core (ui_clk domain) ----
    wire        uart_tx;
    wire [31:0] pc_debug, instr_debug;

    top #(
        .INIT_FILE     (INIT_FILE),
        .UART_BAUD_DIV (16'd723)   // 83.333 MHz / 115200
    ) cpu_top (
        .clk               (ui_clk),
        .rst               (rst_core),
        .software_interrupt(1'b0),
        .external_interrupt(1'b0),
        .uart_tx           (uart_tx),
        .ddr3_req          (ddr3_req),
        .ddr3_we           (ddr3_we),
        .ddr3_addr         (ddr3_addr_off),
        .ddr3_wdata        (ddr3_wdata),
        .ddr3_byte_enable  (ddr3_byte_enable),
        .ddr3_rdata        (ddr3_rdata),
        .ddr3_stall        (ddr3_stall),
        .pc_debug          (pc_debug),
        .instr_debug       (instr_debug)
    );

    assign uart_rxd_out = uart_tx;

    // ---- Status LEDs ----
    reg [25:0] heartbeat;
    always @(posedge ui_clk) heartbeat <= heartbeat + 1'b1;

    assign led[0] = init_calib_complete;  // DDR3 trained
    assign led[1] = heartbeat[25];        // ui_clk alive
    assign led[2] = mmcm_locked;          // clocks locked
    assign led[3] = ~rst_core;            // core running

endmodule
`default_nettype wire
