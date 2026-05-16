// ============================================================
//  fp_regfile.sv  –  32-entry floating-point register file
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
    input  logic [4:0]     rd_addr,
    input  logic [FLEN-1:0] rd_data,
    input  logic           reg_write
);

    logic [FLEN-1:0] regs [31:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integer i;
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= {FLEN{1'b0}};
        end else if (reg_write && (rd_addr != 5'b0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    always_comb begin
        rs1_data = regs[rs1_addr];
        rs2_data = regs[rs2_addr];
        if (reg_write && (rd_addr != 5'b0)) begin
            if (rd_addr == rs1_addr)
                rs1_data = rd_data;
            if (rd_addr == rs2_addr)
                rs2_data = rd_data;
        end
    end

endmodule
