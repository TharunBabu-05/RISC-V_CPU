// ============================================================
//  bram.sv - Banked dual-port block RAM
//
//  Port A fetches one instruction word. Port B reads or writes up to four
//  consecutive bytes beginning at any byte address. Even and odd word banks
//  allow an unaligned 32-bit access to touch two adjacent words in one cycle.
// ============================================================
`timescale 1ns/1ps

module bram #(
    parameter SIZE_BYTES = 65536,
    parameter INIT_FILE  = ""
) (
    input  logic        clk,
    input  logic [31:0] a_addr,
    output logic [31:0] a_rdata,
    input  logic [31:0] b_addr,
    input  logic [31:0] b_wdata,
    input  logic [3:0]  b_we,
    input  logic        b_re,
    output logic [31:0] b_rdata
);

    localparam integer WORDS  = SIZE_BYTES / 4;
    localparam integer ADDR_W = $clog2(WORDS);

    // Both banks use the original word address so the existing firmware.vmem
    // can initialize them directly. Only the parity-matching copy is used.
    (* ram_style = "block" *) logic [31:0] even_mem [0:WORDS-1];
    (* ram_style = "block" *) logic [31:0] odd_mem  [0:WORDS-1];

    generate
        if (INIT_FILE != "") begin : gen_init
            initial begin
                $readmemh(INIT_FILE, even_mem);
                $readmemh(INIT_FILE, odd_mem);
            end
        end
    endgenerate

    logic [31:0] a_even_rdata, a_odd_rdata;
    logic        a_odd_q;

    // Port A is the instruction-fetch side of each true dual-port bank.
    // Register the selected bank alongside its synchronous RAM output.
    always_ff @(posedge clk) begin
        a_odd_q <= a_addr[2];
        if (a_addr[2])
            a_odd_rdata <= odd_mem[a_addr[ADDR_W+1:2]];
        else
            a_even_rdata <= even_mem[a_addr[ADDR_W+1:2]];
    end
    assign a_rdata = a_odd_q ? a_odd_rdata : a_even_rdata;

    // Convert sequential byte enables into byte lanes in the base and next
    // words. b_wdata byte n always belongs at address b_addr+n.
    logic [3:0]  base_we, next_we;
    logic [31:0] base_wdata, next_wdata;
    integer lane;
    always_comb begin
        base_we    = 4'b0;
        next_we    = 4'b0;
        base_wdata = 32'b0;
        next_wdata = 32'b0;
        for (lane = 0; lane < 4; lane = lane + 1) begin
            if (b_we[lane]) begin
                if ((b_addr[1:0] + lane) < 4) begin
                    base_we[b_addr[1:0] + lane] = 1'b1;
                    base_wdata[(b_addr[1:0] + lane)*8 +: 8] = b_wdata[lane*8 +: 8];
                end else begin
                    next_we[b_addr[1:0] + lane - 4] = 1'b1;
                    next_wdata[(b_addr[1:0] + lane - 4)*8 +: 8] = b_wdata[lane*8 +: 8];
                end
            end
        end
    end

    logic [ADDR_W-1:0] base_word_addr;
    logic [ADDR_W-1:0] even_b_addr, odd_b_addr;
    logic [3:0]         even_b_we, odd_b_we;
    logic [31:0]        even_b_wdata, odd_b_wdata;
    logic [31:0]        even_b_rdata, odd_b_rdata;
    logic [2:0]         b_shift_q;

    // Adjacent words always have opposite parity. Selecting one address and
    // one byte-enable vector for each bank gives each inferred RAM exactly
    // one read/write data port, which maps cleanly to FPGA block RAM.
    always_comb begin
        base_word_addr = b_addr[ADDR_W+1:2];
        if (b_addr[2]) begin
            odd_b_addr   = base_word_addr;
            odd_b_we     = base_we;
            odd_b_wdata  = base_wdata;
            even_b_addr  = base_word_addr + 1'b1;
            even_b_we    = next_we;
            even_b_wdata = next_wdata;
        end else begin
            even_b_addr  = base_word_addr;
            even_b_we    = base_we;
            even_b_wdata = base_wdata;
            odd_b_addr   = base_word_addr + 1'b1;
            odd_b_we     = next_we;
            odd_b_wdata  = next_wdata;
        end
    end

    integer even_lane;
    always_ff @(posedge clk) begin
        for (even_lane = 0; even_lane < 4; even_lane = even_lane + 1) begin
            if (even_b_we[even_lane])
                even_mem[even_b_addr][even_lane*8 +: 8] <=
                    even_b_wdata[even_lane*8 +: 8];
        end
        if (b_re)
            even_b_rdata <= even_mem[even_b_addr];
    end

    integer odd_lane;
    always_ff @(posedge clk) begin
        for (odd_lane = 0; odd_lane < 4; odd_lane = odd_lane + 1) begin
            if (odd_b_we[odd_lane])
                odd_mem[odd_b_addr][odd_lane*8 +: 8] <=
                    odd_b_wdata[odd_lane*8 +: 8];
        end
        if (b_re)
            odd_b_rdata <= odd_mem[odd_b_addr];
    end

    always_ff @(posedge clk) begin
        if (b_re)
            b_shift_q <= {b_addr[2], b_addr[1:0]};
    end

    always_comb begin
        if (b_shift_q[2])
            b_rdata = ({even_b_rdata, odd_b_rdata} >> (b_shift_q[1:0] * 8));
        else
            b_rdata = ({odd_b_rdata, even_b_rdata} >> (b_shift_q[1:0] * 8));
    end

endmodule
