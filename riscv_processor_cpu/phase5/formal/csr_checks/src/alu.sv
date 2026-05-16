// ============================================================
//  alu.sv  –  RISC-V RV32/RV64 Arithmetic / Logic Unit
//  Supports: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
// ============================================================
`timescale 1ns/1ps

module alu #(
    parameter int XLEN = 32
) (
    input  logic [XLEN-1:0] a,      // operand A  (rs1 or PC)
    input  logic [XLEN-1:0] b,      // operand B  (rs2 or imm)
    input  logic [ 3:0] alu_ctrl,   // operation select
    output logic [XLEN-1:0] result, // computed result
    output logic        zero        // result == 0  (used by branch)
);

    // ALU control encoding
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;

    localparam int SHAMT_BITS = (XLEN == 64) ? 6 : 5;

    logic [XLEN-1:0] sra_result;
    assign sra_result = $signed(a) >>> b[SHAMT_BITS-1:0];

    always_comb begin
        case (alu_ctrl)
            ALU_ADD  : result = a + b;
            ALU_SUB  : result = a - b;
            ALU_AND  : result = a & b;
            ALU_OR   : result = a | b;
            ALU_XOR  : result = a ^ b;
            ALU_SLL  : result = a << b[SHAMT_BITS-1:0];
            ALU_SRL  : result = a >> b[SHAMT_BITS-1:0];
            ALU_SRA  : result = sra_result;
            ALU_SLT  : result = {{(XLEN-1){1'b0}}, $signed(a) < $signed(b)};
            ALU_SLTU : result = {{(XLEN-1){1'b0}}, a < b};
            default  : result = {XLEN{1'b0}};
        endcase
    end

    assign zero = (result == {XLEN{1'b0}});

endmodule
