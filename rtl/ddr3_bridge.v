`default_nettype none
// Bridges the CPU's single-cycle memory interface to the MIG 7-series native UI.
// One 32-bit access at a time; `stall` holds the pipeline until the access
// completes. Runs in the MIG ui_clk domain. Each MIG command moves one 128-bit
// word, so we pick the 32-bit lane with addr[3:2] and mask the rest on writes.
//
// app_cmd: 000 = write, 001 = read.

module ddr3_bridge (
    input  wire         clk,                 // ui_clk
    input  wire         rst,                 // ui_clk_sync_rst
    input  wire         init_calib_complete, // DDR3 trained

    // CPU side (req asserted only when the DDR3 region is addressed)
    input  wire         req,                 // a DDR3 access this cycle (rd|wr)
    input  wire         we,                  // write (else read)
    input  wire [27:0]  addr,                // byte address into DDR3
    input  wire [31:0]  wdata,
    input  wire [3:0]   byte_enable,
    output reg  [31:0]  rdata,
    output wire         stall,               // hold pipeline while busy / pre-calib

    // MIG native UI
    output reg  [27:0]  app_addr,
    output reg  [2:0]   app_cmd,
    output reg          app_en,
    output reg  [127:0] app_wdf_data,
    output reg  [15:0]  app_wdf_mask,
    output reg          app_wdf_wren,
    output reg          app_wdf_end,
    input  wire         app_rdy,
    input  wire         app_wdf_rdy,
    input  wire [127:0] app_rd_data,
    input  wire         app_rd_data_valid
);
    localparam CMD_WRITE = 3'b000;
    localparam CMD_READ  = 3'b001;

    localparam S_IDLE  = 2'd0;
    localparam S_WRITE = 2'd1;
    localparam S_READ  = 2'd2;
    localparam S_RWAIT = 2'd3;

    reg [1:0] state;
    reg [1:0] lane;       // 32-bit lane within the 128-bit word (addr[3:2])
    reg       cmd_done;   // command (app_en) accepted
    reg       wdf_done;   // write data accepted
    reg       done;       // access complete; drop stall and don't re-fire

    // 16-byte line; native-UI 128-bit words are 8 app_addr units apart (BL8).
    wire [23:0] line = addr[27:4];

    // Stall the CPU from the cycle a DDR3 req appears until `done` pulses.
    assign stall = req && !done;

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            app_en       <= 1'b0;
            app_wdf_wren <= 1'b0;
            app_wdf_end  <= 1'b0;
            cmd_done     <= 1'b0;
            wdf_done     <= 1'b0;
            done         <= 1'b0;
            rdata        <= 32'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    cmd_done <= 1'b0;
                    wdf_done <= 1'b0;
                    if (!req)
                        done <= 1'b0;           // access consumed; arm for next
                    else if (init_calib_complete && !done) begin
                        lane     <= addr[3:2];
                        app_addr <= {line, 3'b000};
                        if (we) begin
                            app_cmd      <= CMD_WRITE;
                            app_en       <= 1'b1;
                            app_wdf_data <= {4{wdata}};         // lane selected by mask
                            app_wdf_mask <= ~(16'h000F << (addr[3:2] * 4));
                            app_wdf_wren <= 1'b1;
                            app_wdf_end  <= 1'b1;
                            state        <= S_WRITE;
                        end else begin
                            app_cmd <= CMD_READ;
                            app_en  <= 1'b1;
                            state   <= S_READ;
                        end
                    end
                end

                S_WRITE: begin
                    if (app_en && app_rdy)           begin app_en <= 1'b0;       cmd_done <= 1'b1; end
                    if (app_wdf_wren && app_wdf_rdy)  begin app_wdf_wren <= 1'b0; app_wdf_end <= 1'b0; wdf_done <= 1'b1; end
                    if ((cmd_done || (app_en && app_rdy)) &&
                        (wdf_done || (app_wdf_wren && app_wdf_rdy))) begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                S_READ: begin
                    if (app_en && app_rdy) begin
                        app_en <= 1'b0;
                        state  <= S_RWAIT;
                    end
                end

                S_RWAIT: begin
                    if (app_rd_data_valid) begin
                        rdata <= app_rd_data[lane*32 +: 32];
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
