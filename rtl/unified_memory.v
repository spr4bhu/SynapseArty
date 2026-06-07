`default_nettype none
`include "memory_map.vh"

// Word-organized dual-port unified memory (instructions + data).
// Both reads are registered (synchronous) so Vivado infers block RAM; writes are
// synchronous with per-byte lane enables. Only naturally-aligned accesses.

module unified_memory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_SIZE   = 16384,  // total bytes across instruction + data regions
    parameter INIT_FILE  = ""      // optional word-per-line hex for synthesis init
) (
    input  wire                  clk,

    // Instruction port (read-only, word-aligned)
    input  wire [ADDR_WIDTH-1:0] addr_instr,
    input  wire                  instr_hold,   // freeze instr_out during a pipeline stall
    output reg  [DATA_WIDTH-1:0] instr_out,

    // Data port (read/write, byte address)
    input  wire [ADDR_WIDTH-1:0] addr_data,
    input  wire [DATA_WIDTH-1:0] write_data,
    output reg  [DATA_WIDTH-1:0] read_data,
    input  wire                  write_enable,
    input  wire [3:0]            byte_enable,   // byte-count enable from memory_unit
    input  wire                  read_enable,
    input  wire [2:0]            load_type      // sign/zero-extension selector
);

    localparam WORDS         = MEM_SIZE / 4;
    localparam WORD_IDX_BITS = (WORDS <= 1) ? 1 : $clog2(WORDS);

    // Word-organized storage
    reg [31:0] mem [0:WORDS-1];

    // Init: simulation uses +define+INSTR_HEX_FILE, synthesis uses the INIT_FILE param.
    integer k;
    initial begin
        for (k = 0; k < WORDS; k = k + 1)
            mem[k] = 32'h00000013;            // NOP fill
`ifdef INSTR_HEX_FILE
        $display("unified_memory: loading instructions from %s", `INSTR_HEX_FILE);
        $readmemh(`INSTR_HEX_FILE, mem);
`else
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
`endif
    end

    // Instruction port: registered read. instr_hold freezes it during a pipeline
    // stall so the in-flight instruction isn't clobbered by a re-read of the held PC.
    wire [WORD_IDX_BITS-1:0] iword = addr_instr[WORD_IDX_BITS+1:2];
    always @(posedge clk) begin
        if (!instr_hold)
            instr_out <= (addr_instr < MEM_SIZE) ? mem[iword]
                                                 : 32'h00000013; // NOP if OOB
    end

    // Data port: registered read; valid the cycle after addr_data (the core's
    // mem_read_stall holds addr_data stable for the extract logic below).
    wire [WORD_IDX_BITS-1:0] dword = addr_data[WORD_IDX_BITS+1:2];
    wire [1:0]  boff  = addr_data[1:0];

    reg  [31:0] rword;
    always @(posedge clk) begin
        rword <= (addr_data < MEM_SIZE) ? mem[dword] : 32'h0;
    end

    // Shift the addressed lane down to bit 0 (shift avoids out-of-range part-selects).
    wire [31:0] rshift = rword >> (boff * 8);
    wire [7:0]  rbyte  = rshift[7:0];
    wire [15:0] rhalf  = rshift[15:0];

    always @(*) begin
        if (read_enable) begin
            case (load_type)
                3'b000:  read_data = {{24{rbyte[7]}}, rbyte};   // LB  (sign-extend)
                3'b100:  read_data = {24'h0, rbyte};            // LBU (zero-extend)
                3'b001:  read_data = {{16{rhalf[15]}}, rhalf};  // LH  (sign-extend)
                3'b101:  read_data = {16'h0, rhalf};            // LHU (zero-extend)
                3'b010:  read_data = rword;                     // LW
                default: read_data = 32'h0;
            endcase
        end else begin
            read_data = 32'h0;
        end
    end

    // Data port write: shift the byte enables and data into the target word's lanes.
    wire [3:0]  lane_be   = byte_enable << boff;
    wire [31:0] lane_data = write_data << (boff * 8);

    always @(posedge clk) begin
        if (write_enable && (addr_data < MEM_SIZE)) begin
            if (lane_be[0]) mem[dword][7:0]   <= lane_data[7:0];
            if (lane_be[1]) mem[dword][15:8]  <= lane_data[15:8];
            if (lane_be[2]) mem[dword][23:16] <= lane_data[23:16];
            if (lane_be[3]) mem[dword][31:24] <= lane_data[31:24];
        end
    end

endmodule
`default_nettype wire
