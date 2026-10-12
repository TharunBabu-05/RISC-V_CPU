// ============================================================
//  fp_regfile.sv  –  32-entry floating-point register file
//  f0 is an ordinary register (unlike x0). Three read ports
//  (rs1, rs2, rs3 for the fused multiply-add instructions) with
//  write-through bypass from the write port.
// ============================================================
`timescale 1ns/1ps

module fp_regfile #(
    parameter int FLEN = 32
) (
    input  logic           clk,
    input  logic           rst_n,
    input  logic [4:0]     rs1_addr,
    output logic [FLEN-1:0] rs1_data,
    input  logic [4:0]     rs2_addr,
    output logic [FLEN-1:0] rs2_data,
    input  logic [4:0]     rs3_addr,
    output logic [FLEN-1:0] rs3_data,
    input  logic [4:0]     rd_addr,
    input  logic [FLEN-1:0] rd_data,
    input  logic           reg_write
);

    logic [FLEN-1:0] regs [31:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i = i + 1)
                regs[i] <= {FLEN{1'b0}};
        end else if (reg_write) begin
            regs[rd_addr] <= rd_data;
        end
    end

    assign rs1_data = (reg_write && rd_addr == rs1_addr) ? rd_data : regs[rs1_addr];
    assign rs2_data = (reg_write && rd_addr == rs2_addr) ? rd_data : regs[rs2_addr];
    assign rs3_data = (reg_write && rd_addr == rs3_addr) ? rd_data : regs[rs3_addr];

endmodule
