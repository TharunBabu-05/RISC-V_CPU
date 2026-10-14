// ============================================================
//  dram_ctrl.sv - Backing-memory controller model
//
//  This controller arbitrates normal CPU traffic and page-table reads over a
//  byte-addressable memory array. The interface is intentionally zero-wait to
//  match the current L2 contract; an external DDR PHY can replace this module
//  later without changing cache policy.
// ============================================================
`timescale 1ns/1ps

module dram_ctrl #(
    parameter int XLEN = 32,
    parameter int WORDS = 1024
) (
    input  logic            clk,
    input  logic [XLEN-1:0] addr,
    input  logic [XLEN-1:0] wr_data,
    input  logic            mem_read,
    input  logic            mem_write,
    input  logic [2:0]      funct3,
    output logic [XLEN-1:0] rd_data,
    input  logic            ptw_read,
    input  logic [XLEN-1:0] ptw_addr,
    output logic [31:0]     ptw_rdata
);
    logic [31:0] read_count, write_count, ptw_count;

    data_mem #(.XLEN(XLEN), .WORDS(WORDS)) u_dmem (
        .clk(clk), .addr(addr), .wr_data(wr_data),
        .mem_read(mem_read), .mem_write(mem_write), .funct3(funct3),
        .rd_data(rd_data), .ptw_read(ptw_read), .ptw_addr(ptw_addr),
        .ptw_rdata(ptw_rdata)
    );

    initial begin
        read_count = 0;
        write_count = 0;
        ptw_count = 0;
    end

    always_ff @(posedge clk) begin
        if (mem_read)
            read_count <= read_count + 1;
        if (mem_write)
            write_count <= write_count + 1;
        if (ptw_read)
            ptw_count <= ptw_count + 1;
    end
endmodule
