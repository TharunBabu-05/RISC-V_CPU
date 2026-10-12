// ============================================================
//  control_unit.sv  –  Main decoder: opcode → control signals
//  Plus alu_control sub-decoder (funct3 / funct7)
// ============================================================
`timescale 1ns/1ps

module control_unit (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic [4:0] rs2_imm,
    // Datapath control signals
    output logic       reg_write,   // write result to rd
    output logic       alu_src,     // 0=rs2, 1=immediate
    output logic       mem_read,    // load from data memory
    output logic       mem_write,   // store to data memory
    output logic       mem_to_reg,  // 0=ALU result, 1=mem data
    output logic       branch,      // conditional branch instruction
    output logic       jump,        // unconditional jump (JAL/JALR)
    output logic [1:0] alu_op,      // 00=add, 01=sub, 10=R-type/I-type
    output logic       csr_en,      // CSR instruction
    output logic [2:0] csr_op,      // CSR operation encoding
    output logic       ecall,       // ECALL instruction
    output logic       ebreak,      // EBREAK instruction
    output logic [3:0] alu_ctrl,    // to ALU
    output logic       muldiv_en,   // M extension instruction
    output logic [2:0] muldiv_op    // M extension funct3
);

    // Opcode constants
    localparam OP_R     = 7'b0110011;
    localparam OP_IMM   = 7'b0010011;
    localparam OP_LOAD  = 7'b0000011;
    localparam OP_STORE = 7'b0100011;
    localparam OP_BRANCH= 7'b1100011;
    localparam OP_LUI   = 7'b0110111;
    localparam OP_AUIPC = 7'b0010111;
    localparam OP_JAL   = 7'b1101111;
    localparam OP_JALR  = 7'b1100111;
    localparam OP_SYSTEM= 7'b1110011;

    // CSR op encoding (matches funct3 patterns)
    localparam [2:0]
        CSR_NONE = 3'b000,
        CSR_RW   = 3'b001,
        CSR_RS   = 3'b010,
        CSR_RC   = 3'b011,
        CSR_RWI  = 3'b101,
        CSR_RSI  = 3'b110,
        CSR_RCI  = 3'b111;

    // Main decoder
    always_comb begin
        // Defaults
        reg_write  = 1'b0;
        alu_src    = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        branch     = 1'b0;
        jump       = 1'b0;
        alu_op     = 2'b00;
        csr_en     = 1'b0;
        csr_op     = CSR_NONE;
        ecall      = 1'b0;
        ebreak     = 1'b0;
        muldiv_en  = 1'b0;
        muldiv_op  = 3'b000;

        case (opcode)
            OP_R: begin
                if (funct7 == 7'b0000001) begin
                    reg_write = 1'b1;
                    muldiv_en = 1'b1;
                    muldiv_op = funct3;
                end else begin
                    reg_write = 1'b1;
                    alu_op    = 2'b10;
                end
            end
            OP_IMM: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 2'b10;
            end
            OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
            end
            OP_STORE: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
            end
            OP_BRANCH: begin
                branch = 1'b1;
                alu_op = 2'b01;
            end
            OP_LUI: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                // ALU just passes immediate (ADD 0 + imm)
            end
            OP_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                // PC + imm computed in EX
            end
            OP_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
            end
            OP_JALR: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jump      = 1'b1;
            end
            OP_SYSTEM: begin
                case (funct3)
                    3'b000: begin
                        // ECALL/EBREAK are encoded in imm[11:0]
                        ecall  = (funct7 == 7'b0000000) && (rs2_imm == 5'b00000);
                        ebreak = (funct7 == 7'b0000000) && (rs2_imm == 5'b00001);
                    end
                    CSR_RW, CSR_RS, CSR_RC,
                    CSR_RWI, CSR_RSI, CSR_RCI: begin
                        reg_write = 1'b1;
                        csr_en    = 1'b1;
                        csr_op    = funct3;
                    end
                    default: ;
                endcase
            end
            default: ;
        endcase
    end

    // ALU control sub-decoder
    // alu_op 00 → ADD (load/store address), 01 → SUB (branch), 10 → funct3/funct7
    localparam [3:0]
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_AND  = 4'b0010,
        ALU_OR   = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SLL  = 4'b0101,
        ALU_SRL  = 4'b0110,
        ALU_SRA  = 4'b0111,
        ALU_SLT  = 4'b1000,
        ALU_SLTU = 4'b1001;

    always_comb begin
        case (alu_op)
            2'b00: alu_ctrl = ALU_ADD;
            2'b01: alu_ctrl = ALU_SUB;
            2'b10: begin
                case (funct3)
                    // SUB is only valid for R-type (funct7=0100000). For ADDI this must stay ADD.
                    3'b000: alu_ctrl = ((opcode == OP_R) && funct7[5]) ? ALU_SUB : ALU_ADD;
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                    default: alu_ctrl = ALU_ADD;
                endcase
            end
            default: alu_ctrl = ALU_ADD;
        endcase
    end

endmodule


// ============================================================
//  illegal_detect  –  Flags encodings this core does not implement
//
//  Covers RV32I/RV64I base, M, Zicsr (CSR address checks happen in
//  EX, where the privilege level is known), FENCE/FENCE.I (executed
//  as NOPs), WFI (NOP), SFENCE.VMA, and the FP/vector stub opcodes.
//  Anything else raises an illegal-instruction exception (mcause 2).
// ============================================================
module illegal_detect #(
    parameter int XLEN = 32
) (
    input  logic [31:0] instr,
    output logic        illegal
);

    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];

    // Shift-immediate upper bits: RV32 uses imm[11:5], RV64 uses imm[11:6]
    logic shamt_ok_sll, shamt_ok_sr;
    always_comb begin
        if (XLEN == 64) begin
            shamt_ok_sll = (instr[31:26] == 6'b000000);
            shamt_ok_sr  = (instr[31:26] == 6'b000000) || (instr[31:26] == 6'b010000);
        end else begin
            shamt_ok_sll = (funct7 == 7'b0000000);
            shamt_ok_sr  = (funct7 == 7'b0000000) || (funct7 == 7'b0100000);
        end
    end

    always_comb begin
        illegal = 1'b1;
        case (opcode)
            7'b0110111,                                   // LUI
            7'b0010111,                                   // AUIPC
            7'b1101111: illegal = 1'b0;                   // JAL
            7'b1100111: illegal = (funct3 != 3'b000);     // JALR
            7'b1100011: illegal = (funct3 == 3'b010) || (funct3 == 3'b011);   // BRANCH
            7'b0000011: begin                             // LOAD
                case (funct3)
                    3'b000, 3'b001, 3'b010, 3'b100, 3'b101: illegal = 1'b0;
                    3'b011, 3'b110: illegal = (XLEN != 64);              // LD, LWU
                    default: illegal = 1'b1;
                endcase
            end
            7'b0100011: begin                             // STORE
                case (funct3)
                    3'b000, 3'b001, 3'b010: illegal = 1'b0;
                    3'b011: illegal = (XLEN != 64);                       // SD
                    default: illegal = 1'b1;
                endcase
            end
            7'b0010011: begin                             // OP-IMM
                case (funct3)
                    3'b001:  illegal = !shamt_ok_sll;
                    3'b101:  illegal = !shamt_ok_sr;
                    default: illegal = 1'b0;
                endcase
            end
            7'b0110011: begin                             // OP (incl. M)
                case (funct7)
                    7'b0000000, 7'b0000001: illegal = 1'b0;
                    7'b0100000: illegal = !((funct3 == 3'b000) || (funct3 == 3'b101));  // SUB, SRA
                    default:    illegal = 1'b1;
                endcase
            end
            7'b0001111: illegal = !((funct3 == 3'b000) || (funct3 == 3'b001));   // FENCE, FENCE.I
            7'b1110011: begin                             // SYSTEM
                case (funct3)
                    3'b000: illegal = !((instr == 32'h0000_0073) ||   // ECALL
                                        (instr == 32'h0010_0073) ||   // EBREAK
                                        (instr == 32'h3020_0073) ||   // MRET
                                        (instr == 32'h1020_0073) ||   // SRET
                                        (instr == 32'h1050_0073) ||   // WFI
                                        ((funct7 == 7'b0001001) && (instr[11:7] == 5'b0)));  // SFENCE.VMA
                    3'b100: illegal = 1'b1;
                    default: illegal = 1'b0;              // CSR ops: address checked in EX
                endcase
            end
            // FP / vector stubs (see fpu_unit.sv, vector_unit.sv)
            7'b0000111: illegal = (funct3 != 3'b010);     // FLW
            7'b0100111: illegal = (funct3 != 3'b010);     // FSW
            7'b1010011: illegal = !((funct7 == 7'b0000000) || (funct7 == 7'b0000100) ||
                                    (funct7 == 7'b0001000) || (funct7 == 7'b0001100));  // FADD/FSUB/FMUL/FDIV.S
            7'b1010111: illegal = (funct3 > 3'b100);      // vector stub ops 0-4
            default:    illegal = 1'b1;
        endcase
    end

endmodule
