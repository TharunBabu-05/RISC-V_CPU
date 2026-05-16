// ============================================================
//  imm_gen.sv  –  Immediate value generator for RV32/RV64 formats
//  Formats: I, S, B, U, J
// ============================================================
`timescale 1ns/1ps

module imm_gen #(
    parameter int XLEN = 32
) (
    input  logic [31:0] instr,
    output logic [XLEN-1:0] imm_out
);

    logic [6:0] opcode;
    assign opcode = instr[6:0];

    // Opcode constants
    localparam OP_IMM   = 7'b0010011; // I-type arithmetic
    localparam OP_LOAD  = 7'b0000011; // I-type load
    localparam OP_LOAD_FP  = 7'b0000111; // I-type FP load
    localparam OP_JALR  = 7'b1100111; // I-type JALR
    localparam OP_STORE = 7'b0100011; // S-type
    localparam OP_STORE_FP = 7'b0100111; // S-type FP store
    localparam OP_BRANCH= 7'b1100011; // B-type
    localparam OP_LUI   = 7'b0110111; // U-type
    localparam OP_AUIPC = 7'b0010111; // U-type
    localparam OP_JAL   = 7'b1101111; // J-type

    logic [31:0] imm32;

    always_comb begin
        case (opcode)
            OP_IMM, OP_LOAD, OP_LOAD_FP, OP_JALR:
                // I-type: sign-extend bits[31:20]
                imm32 = {{20{instr[31]}}, instr[31:20]};

            OP_STORE, OP_STORE_FP:
                // S-type: imm[11:5] in bits[31:25], imm[4:0] in bits[11:7]
                imm32 = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            OP_BRANCH:
                // B-type: instr[31], instr[7], instr[30:25], instr[11:8], 0
                imm32 = {{19{instr[31]}}, instr[31], instr[7],
                          instr[30:25], instr[11:8], 1'b0};

            OP_LUI, OP_AUIPC:
                // U-type: upper 20 bits, lower 12 zeroed
                imm32 = {instr[31:12], 12'b0};

            OP_JAL:
                // J-type: instr[31], instr[19:12], instr[20], instr[30:21], 0
                imm32 = {{11{instr[31]}}, instr[31], instr[19:12],
                          instr[20], instr[30:21], 1'b0};

            default:
                imm32 = 32'b0;
        endcase
    end

    // Sign-extend 32-bit immediate to XLEN
    always_comb begin
        imm_out = {{(XLEN-32){imm32[31]}}, imm32};
    end

endmodule
