// ============================================================
//  dram_ctrl.sv  –  DRAM controller stub (pass-through)
// ============================================================
`timescale 1ns/1ps

module dram_ctrl #(
    parameter int XLEN = 32
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

    // Pass-through to data memory (replace with real DRAM controller later)
    data_mem #(.XLEN(XLEN)) u_dmem (
        .clk      (clk),
        .addr     (addr),
        .wr_data  (wr_data),
        .mem_read (mem_read),
        .mem_write(mem_write),
        .funct3   (funct3),
        .rd_data  (rd_data),
        .ptw_read (ptw_read),
        .ptw_addr (ptw_addr),
        .ptw_rdata(ptw_rdata)
    );

endmodule
