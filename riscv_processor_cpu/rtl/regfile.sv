// ============================================================
//  regfile.sv  –  32 × XLEN register file
//  x0 is hardwired to zero.  Synchronous write, async read.
// ============================================================
`timescale 1ns/1ps

module regfile #(
    parameter int XLEN = 32,
    parameter bit SECOND_PORT = 1'b0
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
    input  logic        reg_write,
    input  logic [4:0] rs1_second, rs2_second, rd_second,
    input  logic [XLEN-1:0] data_second,
    input  logic write_second,
    output logic [XLEN-1:0] rs1_second_data, rs2_second_data
);

    logic [XLEN-1:0] regs [0:31];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= {XLEN{1'b0}};
        end else begin
            if (reg_write && rd_addr != 5'b0) regs[rd_addr] <= rd_data;
            if (SECOND_PORT && write_second && rd_second != 0)
                regs[rd_second] <= data_second;
        end
    end

    // Asynchronous reads with write-first bypass; x0 always returns 0
    assign rs1_data = (rs1_addr == 5'b0) ? {XLEN{1'b0}} :
                      (SECOND_PORT && write_second && rd_second == rs1_addr) ? data_second :
                      ((reg_write && rd_addr == rs1_addr && rd_addr != 5'b0) ? rd_data : regs[rs1_addr]);
    assign rs2_data = (rs2_addr == 5'b0) ? {XLEN{1'b0}} :
                      (SECOND_PORT && write_second && rd_second == rs2_addr) ? data_second :
                      ((reg_write && rd_addr == rs2_addr && rd_addr != 5'b0) ? rd_data : regs[rs2_addr]);

    assign rs1_second_data = !SECOND_PORT || rs1_second == 0 ? '0 :
        (write_second && rd_second == rs1_second) ? data_second :
        (reg_write && rd_addr == rs1_second) ? rd_data : regs[rs1_second];
    assign rs2_second_data = !SECOND_PORT || rs2_second == 0 ? '0 :
        (write_second && rd_second == rs2_second) ? data_second :
        (reg_write && rd_addr == rs2_second) ? rd_data : regs[rs2_second];

endmodule
