// ============================================================
//  icache.sv - Direct-mapped instruction cache with backing ROM
//
//  The current CPU fetch interface has no ready signal, so misses are serviced
//  by a zero-wait read-through path and installed on the following edge. This
//  models real tags/data/hits while preserving the existing pipeline contract.
// ============================================================
`timescale 1ns/1ps

module icache #(
    parameter int XLEN = 32,
    parameter IMEM_FILE = "",
    parameter int WORDS = 1024,
    parameter int LINES = 64
) (
    input  logic            clk,
    input  logic            rst_n,
    input  logic            invalidate,
    input  logic [XLEN-1:0] addr,
    output logic [31:0]     instr
);
    localparam int MEM_AW = $clog2(WORDS);
    localparam int INDEX_BITS = $clog2(LINES);
    localparam int TAG_BITS = XLEN - 2 - INDEX_BITS;

    // Kept as `mem` for firmware/testbench initialization compatibility.
    logic [31:0] mem [0:WORDS-1];
    logic [31:0] cache_data [0:LINES-1];
    logic [TAG_BITS-1:0] cache_tag [0:LINES-1];
    logic [LINES-1:0] cache_valid;
    logic [INDEX_BITS-1:0] index;
    logic [TAG_BITS-1:0] tag;
    logic hit;
    logic [31:0] backing_word;
    integer i;

    assign index = addr[INDEX_BITS+1:2];
    assign tag = addr[XLEN-1:INDEX_BITS+2];
    assign hit = cache_valid[index] && cache_tag[index] == tag;
    assign backing_word = mem[addr[MEM_AW+1:2]];
    assign instr = hit ? cache_data[index] : backing_word;

    initial begin
        cache_valid = {LINES{1'b0}};
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h0000_0013;
        for (i = 0; i < LINES; i = i + 1) begin
            cache_data[i] = 32'h0000_0013;
            cache_tag[i] = {TAG_BITS{1'b0}};
        end
        if (IMEM_FILE != "")
            $readmemh(IMEM_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (!rst_n || invalidate) begin
            cache_valid <= {LINES{1'b0}};
        end else if (!hit) begin
            cache_data[index] <= backing_word;
            cache_tag[index] <= tag;
            cache_valid[index] <= 1'b1;
        end
    end
endmodule
