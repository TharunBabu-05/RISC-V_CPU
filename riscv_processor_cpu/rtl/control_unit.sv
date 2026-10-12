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
//  EX, where the privilege level is known), FENCE/FENCE.I, WFI (NOP)
//  and SFENCE.VMA. The F and V opcode spaces are decoded by ext_decode.
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
            // F / V opcodes are decoded by ext_decode, which overrides this result
            default:    illegal = 1'b1;
        endcase
    end

endmodule


// ============================================================
//  ext_decode  –  F (RV32F) and V (RVV 1.0 subset) instruction decoder
//
//  Used in ID (register sources, write enables, legality) and again
//  in EX on the pipelined instruction word (operation details).
//
//  Vector subset (VLEN = 128, ELEN = 32, LMUL = 1, SEW = 8/16/32):
//    vsetvli vsetivli vsetvl
//    vle8/16/32.v vse8/16/32.v           (unit-stride, EEW must equal SEW)
//    vadd vsub vrsub vand vor vxor vsll vsrl vsra
//    vminu vmin vmaxu vmax vmul           (.vv / .vx / .vi as RVV allows)
//    vmseq vmsne vmsltu vmslt vmsleu vmsle vmsgtu vmsgt
//    vmerge.v[vxi]m vmv.v.[vxi] vredsum.vs vmv.x.s vmv.s.x
//  Masked execution (vm = 0, mask in v0) is supported. Anything else in
//  the vector opcode space is reported as illegal.
// ============================================================
module ext_decode #(
    parameter bit HAS_FPU = 1'b1,
    parameter bit HAS_VEC = 1'b1
) (
    input  logic [31:0] instr,
    output logic        is_ext,     // opcode lies in the F/V space
    output logic        illegal,    // F/V encoding not implemented here
    // F
    output logic        f_any,      // any F instruction (gated by mstatus.FS)
    output logic        f_op_en,    // executes on the FPU
    output logic [4:0]  f_op,
    output logic        f_uses_rm,
    output logic        f_load,     // FLW
    output logic        f_store,    // FSW
    output logic        f_wr_fp,    // writes f[rd]
    output logic        f_wr_int,   // writes x[rd]
    output logic        f_src1,     // reads f[rs1]
    output logic        f_src2,     // reads f[rs2]
    output logic        f_src3,     // reads f[rs3]
    // V
    output logic        v_any,      // any vector instruction
    output logic        v_cfg,      // vsetvli / vsetivli / vsetvl
    output logic        v_arith,    // executes on the vector unit
    output logic        v_load,
    output logic        v_store,
    output logic [1:0]  v_eew,      // load/store element width: 0=8, 1=16, 2=32
    output logic        v_wr_vec,   // writes v[vd]
    output logic        v_wr_int,   // writes x[rd]
    output logic        v_src1,     // reads vs1
    output logic        v_src2,     // reads vs2
    output logic        v_srcd,     // reads vd (undisturbed elements) or vs3 (stores)
    output logic        v_src0      // reads the v0 mask
);

    logic [6:0] opcode, funct7;
    logic [5:0] funct6;
    logic [2:0] funct3;
    logic [4:0] rs1f, rs2f, rdf;
    logic       vm;
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    assign funct6 = instr[31:26];
    assign vm     = instr[25];
    assign rs1f   = instr[19:15];
    assign rs2f   = instr[24:20];
    assign rdf    = instr[11:7];

    localparam [6:0] OP_LOAD_FP = 7'b0000111, OP_STORE_FP = 7'b0100111, OP_FP = 7'b1010011,
                     OP_FMADD = 7'b1000011, OP_FMSUB = 7'b1000111, OP_FNMSUB = 7'b1001011,
                     OP_FNMADD = 7'b1001111, OP_V = 7'b1010111;

    // fpu_unit operation codes
    localparam [4:0]
        FADD = 5'd0,  FSUB = 5'd1,  FMUL = 5'd2,  FDIV = 5'd3,  FSQRT = 5'd4,
        FMIN = 5'd5,  FMAX = 5'd6,  FSGNJ = 5'd7, FSGNJN = 5'd8, FSGNJX = 5'd9,
        FEQ = 5'd10,  FLT = 5'd11,  FLE = 5'd12,  FCLASS = 5'd13,
        FCVT_W_S = 5'd14, FCVT_WU_S = 5'd15, FCVT_S_W = 5'd16, FCVT_S_WU = 5'd17,
        FMV_X_W = 5'd18,  FMV_W_X = 5'd19,
        FMADD = 5'd20, FMSUB = 5'd21, FNMSUB = 5'd22, FNMADD = 5'd23;

    // Decode into local variables, then drive every output exactly once
    // (keeps simulators from re-triggering the block on its own writes).
    always_comb begin
        logic f_ok, v_ok, f_dec_op;
        logic [4:0] op;
        logic uses_rm, ld, st, wfp, wint, s1, s2, s3;
        logic cfg, ar, vld, vst, wvec, wvint, vs1, vs2, vsd, vs0;
        logic [1:0] eew;
        logic ext;

        f_ok = 1'b0; v_ok = 1'b0; f_dec_op = 1'b0; op = 5'd0;
        uses_rm = 1'b0; ld = 1'b0; st = 1'b0; wfp = 1'b0; wint = 1'b0; s1 = 1'b0; s2 = 1'b0; s3 = 1'b0;
        cfg = 1'b0; ar = 1'b0; vld = 1'b0; vst = 1'b0; wvec = 1'b0; wvint = 1'b0;
        vs1 = 1'b0; vs2 = 1'b0; vsd = 1'b0; vs0 = 1'b0; eew = 2'd0;

        ext = (opcode == OP_LOAD_FP) || (opcode == OP_STORE_FP) || (opcode == OP_FP) ||
              (opcode == OP_FMADD) || (opcode == OP_FMSUB) || (opcode == OP_FNMSUB) ||
              (opcode == OP_FNMADD) || (opcode == OP_V);

        // ---------------- F ----------------
        case (opcode)
            OP_LOAD_FP: if (funct3 == 3'b010) begin
                f_ok = 1'b1; ld = 1'b1; wfp = 1'b1;
            end
            OP_STORE_FP: if (funct3 == 3'b010) begin
                f_ok = 1'b1; st = 1'b1; s2 = 1'b1;
            end
            OP_FMADD, OP_FMSUB, OP_FNMSUB, OP_FNMADD: if (instr[26:25] == 2'b00) begin
                f_ok = 1'b1; f_dec_op = 1'b1; uses_rm = 1'b1; wfp = 1'b1;
                s1 = 1'b1; s2 = 1'b1; s3 = 1'b1;
                op = (opcode == OP_FMADD) ? FMADD : (opcode == OP_FMSUB) ? FMSUB :
                     (opcode == OP_FNMSUB) ? FNMSUB : FNMADD;
            end
            OP_FP: begin
                case (funct7)
                    7'b0000000, 7'b0000100, 7'b0001000, 7'b0001100: begin
                        f_ok = 1'b1; uses_rm = 1'b1; wfp = 1'b1; s1 = 1'b1; s2 = 1'b1;
                        op = (funct7 == 7'b0000000) ? FADD : (funct7 == 7'b0000100) ? FSUB :
                             (funct7 == 7'b0001000) ? FMUL : FDIV;
                    end
                    7'b0101100: if (rs2f == 5'd0) begin
                        f_ok = 1'b1; uses_rm = 1'b1; wfp = 1'b1; s1 = 1'b1; op = FSQRT;
                    end
                    7'b0010000: if (funct3 <= 3'b010) begin
                        f_ok = 1'b1; wfp = 1'b1; s1 = 1'b1; s2 = 1'b1;
                        op = (funct3 == 3'b000) ? FSGNJ : (funct3 == 3'b001) ? FSGNJN : FSGNJX;
                    end
                    7'b0010100: if (funct3 <= 3'b001) begin
                        f_ok = 1'b1; wfp = 1'b1; s1 = 1'b1; s2 = 1'b1;
                        op = (funct3 == 3'b000) ? FMIN : FMAX;
                    end
                    7'b1100000: if (rs2f <= 5'd1) begin
                        f_ok = 1'b1; uses_rm = 1'b1; wint = 1'b1; s1 = 1'b1;
                        op = rs2f[0] ? FCVT_WU_S : FCVT_W_S;
                    end
                    7'b1010000: if (funct3 <= 3'b010) begin
                        f_ok = 1'b1; wint = 1'b1; s1 = 1'b1; s2 = 1'b1;
                        op = (funct3 == 3'b010) ? FEQ : (funct3 == 3'b001) ? FLT : FLE;
                    end
                    7'b1110000: if (rs2f == 5'd0 && funct3 <= 3'b001) begin
                        f_ok = 1'b1; wint = 1'b1; s1 = 1'b1;
                        op = funct3[0] ? FCLASS : FMV_X_W;
                    end
                    7'b1101000: if (rs2f <= 5'd1) begin
                        f_ok = 1'b1; uses_rm = 1'b1; wfp = 1'b1;
                        op = rs2f[0] ? FCVT_S_WU : FCVT_S_W;
                    end
                    7'b1111000: if (rs2f == 5'd0 && funct3 == 3'b000) begin
                        f_ok = 1'b1; wfp = 1'b1; op = FMV_W_X;
                    end
                    default: ;
                endcase
                f_dec_op = f_ok;
            end
            default: ;
        endcase
        // rm = 101 / 110 are reserved encodings
        if (!HAS_FPU || (uses_rm && (funct3 == 3'b101 || funct3 == 3'b110))) f_ok = 1'b0;
        if (!f_ok) begin
            f_dec_op = 1'b0; ld = 1'b0; st = 1'b0; wfp = 1'b0; wint = 1'b0;
            s1 = 1'b0; s2 = 1'b0; s3 = 1'b0; uses_rm = 1'b0;
        end

        // ---------------- V ----------------
        if ((opcode == OP_LOAD_FP || opcode == OP_STORE_FP) &&
            (funct3 == 3'b000 || funct3 == 3'b101 || funct3 == 3'b110) &&
            (instr[31:26] == 6'b000000) && (rs2f == 5'd0)) begin     // nf=0, mew=0, unit stride
            v_ok = 1'b1;
            eew  = (funct3 == 3'b000) ? 2'd0 : (funct3 == 3'b101) ? 2'd1 : 2'd2;
            vs0  = !vm;
            vsd  = 1'b1;                                              // old vd / vs3
            if (opcode == OP_LOAD_FP) begin
                vld = 1'b1; wvec = 1'b1;
                if (!vm && rdf == 5'd0) v_ok = 1'b0;                  // vd may not overlap the mask
            end else
                vst = 1'b1;
        end else if (opcode == OP_V) begin
            case (funct3)
                3'b111: begin                                         // OPCFG
                    if (!instr[31] || instr[31:30] == 2'b11 || funct7 == 7'b1000000) begin
                        v_ok = 1'b1; cfg = 1'b1; wvint = 1'b1;
                    end
                end
                3'b000, 3'b011, 3'b100: begin                         // OPIVV / OPIVI / OPIVX
                    ar = 1'b1;
                    case (funct6)
                        6'b000000, 6'b001001, 6'b001010, 6'b001011,
                        6'b011000, 6'b011001, 6'b011100, 6'b011101,
                        6'b100101, 6'b101000, 6'b101001:           v_ok = 1'b1;              // vv vx vi
                        6'b000010, 6'b000100, 6'b000101, 6'b000110, 6'b000111,
                        6'b011010, 6'b011011:                      v_ok = (funct3 != 3'b011); // vv vx
                        6'b000011, 6'b011110, 6'b011111:           v_ok = (funct3 != 3'b000); // vx vi
                        6'b010111:                                 v_ok = vm ? (rs2f == 5'd0) : 1'b1; // vmv / vmerge
                        default:                                   v_ok = 1'b0;
                    endcase
                    vs1  = (funct3 == 3'b000);
                    vs2  = !(funct6 == 6'b010111 && vm);              // vmv.v.* has no vs2
                    vs0  = !vm;
                    vsd  = 1'b1;
                    wvec = 1'b1;
                    // a masked op that is not mask-producing may not overwrite v0
                    if (!vm && rdf == 5'd0 && funct6[5:3] != 3'b011) v_ok = 1'b0;
                end
                3'b010: begin                                         // OPMVV
                    ar = 1'b1;
                    if (funct6 == 6'b100101 || funct6 == 6'b000000) begin   // vmul.vv, vredsum.vs
                        v_ok = !(funct6 == 6'b100101 && !vm && rdf == 5'd0);
                        vs1 = 1'b1; vs2 = 1'b1; vsd = 1'b1; vs0 = !vm; wvec = 1'b1;
                    end else if (funct6 == 6'b010000 && rs1f == 5'd0 && vm) begin  // vmv.x.s
                        v_ok = 1'b1; vs2 = 1'b1; wvint = 1'b1;
                    end
                end
                3'b110: begin                                         // OPMVX
                    ar = 1'b1;
                    if (funct6 == 6'b100101) begin                    // vmul.vx
                        v_ok = !(!vm && rdf == 5'd0);
                        vs2 = 1'b1; vsd = 1'b1; vs0 = !vm; wvec = 1'b1;
                    end else if (funct6 == 6'b010000 && rs2f == 5'd0 && vm) begin  // vmv.s.x
                        v_ok = 1'b1; vsd = 1'b1; wvec = 1'b1;
                    end
                end
                default: ;
            endcase
        end
        if (!HAS_VEC) v_ok = 1'b0;
        if (!v_ok) begin
            cfg = 1'b0; ar = 1'b0; vld = 1'b0; vst = 1'b0; wvec = 1'b0; wvint = 1'b0;
            vs1 = 1'b0; vs2 = 1'b0; vsd = 1'b0; vs0 = 1'b0;
        end

        is_ext    = ext;
        illegal   = ext && !f_ok && !v_ok;
        f_any     = f_ok;
        f_op_en   = f_dec_op;
        f_op      = op;
        f_uses_rm = uses_rm;
        f_load    = ld;
        f_store   = st;
        f_wr_fp   = wfp;
        f_wr_int  = wint;
        f_src1    = s1;
        f_src2    = s2;
        f_src3    = s3;
        v_any     = v_ok;
        v_cfg     = cfg;
        v_arith   = ar;
        v_load    = vld;
        v_store   = vst;
        v_eew     = eew;
        v_wr_vec  = wvec;
        v_wr_int  = wvint;
        v_src1    = vs1;
        v_src2    = vs2;
        v_srcd    = vsd;
        v_src0    = vs0;
    end

endmodule
