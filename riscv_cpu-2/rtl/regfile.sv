// ============================================================
//  regfile.sv  –  32 × XLEN register file
//  x0 is hardwired to zero.  Synchronous write, async read.
// ============================================================
`timescale 1ns/1ps

module regfile #(
    parameter int XLEN = 32
) (
    input  logic        clk,
    input  logic        rst_n,
    // Read port 1 (rs1)
    input  logic [4:0]  rs1_addr,
    output logic [XLEN-1:0] rs1_data,
    // Read port 2 (rs2)
    input  logic [4:0]  rs2_addr,
    output logic [XLEN-1:0] rs2_data,
    // Write port (rd)
    input  logic [4:0]  rd_addr,
    input  logic [XLEN-1:0] rd_data,
    input  logic        reg_write
);

    logic [XLEN-1:0] regs [0:31];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= {XLEN{1'b0}};
        end else if (reg_write && rd_addr != 5'b0) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // Asynchronous reads with write-first bypass; x0 always returns 0
    assign rs1_data = (rs1_addr == 5'b0) ? {XLEN{1'b0}} :
                      ((reg_write && rd_addr == rs1_addr && rd_addr != 5'b0) ? rd_data : regs[rs1_addr]);
    assign rs2_data = (rs2_addr == 5'b0) ? {XLEN{1'b0}} :
                      ((reg_write && rd_addr == rs2_addr && rd_addr != 5'b0) ? rd_data : regs[rs2_addr]);

endmodule
