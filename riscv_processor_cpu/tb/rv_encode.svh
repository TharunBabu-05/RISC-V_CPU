// ============================================================
//  rv_encode.svh  –  RISC-V instruction encoders for testbenches
//  `include inside a module (compile with -I tb).
// ============================================================

localparam logic [31:0] RV_NOP = 32'h0000_0013;

function automatic [31:0] rv_r(input [6:0] f7, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
    rv_r = {f7, rs2, rs1, f3, rd, op};
endfunction
function automatic [31:0] rv_i(input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
    rv_i = {imm, rs1, f3, rd, op};
endfunction
function automatic [31:0] rv_s(input [11:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] f3);
    rv_s = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
endfunction
function automatic [31:0] rv_b(input [12:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] f3);
    rv_b = {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
endfunction

function automatic [31:0] rv_addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm); rv_addi = rv_i(imm, rs1, 3'b000, rd, 7'b0010011); endfunction
function automatic [31:0] rv_slli(input [4:0] rd, input [4:0] rs1, input [5:0] sh);  rv_slli = rv_i({6'b0, sh}, rs1, 3'b001, rd, 7'b0010011); endfunction
function automatic [31:0] rv_add (input [4:0] rd, input [4:0] rs1, input [4:0] rs2); rv_add  = rv_r(7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011); endfunction
function automatic [31:0] rv_div (input [4:0] rd, input [4:0] rs1, input [4:0] rs2); rv_div  = rv_r(7'b0000001, rs2, rs1, 3'b100, rd, 7'b0110011); endfunction
function automatic [31:0] rv_lui (input [4:0] rd, input [19:0] imm);                 rv_lui  = {imm, rd, 7'b0110111}; endfunction
function automatic [31:0] rv_lw  (input [4:0] rd, input [4:0] rs1, input [11:0] imm); rv_lw   = rv_i(imm, rs1, 3'b010, rd, 7'b0000011); endfunction
function automatic [31:0] rv_lh  (input [4:0] rd, input [4:0] rs1, input [11:0] imm); rv_lh   = rv_i(imm, rs1, 3'b001, rd, 7'b0000011); endfunction
function automatic [31:0] rv_sw  (input [4:0] rs2, input [4:0] rs1, input [11:0] imm); rv_sw  = rv_s(imm, rs2, rs1, 3'b010); endfunction
function automatic [31:0] rv_beq (input [4:0] rs1, input [4:0] rs2, input [12:0] imm); rv_beq = rv_b(imm, rs2, rs1, 3'b000); endfunction
function automatic [31:0] rv_bne (input [4:0] rs1, input [4:0] rs2, input [12:0] imm); rv_bne = rv_b(imm, rs2, rs1, 3'b001); endfunction
function automatic [31:0] rv_jal (input [4:0] rd, input [20:0] imm);
    rv_jal = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
endfunction
function automatic [31:0] rv_jalr(input [4:0] rd, input [4:0] rs1, input [11:0] imm); rv_jalr = rv_i(imm, rs1, 3'b000, rd, 7'b1100111); endfunction
function automatic [31:0] rv_csrrw(input [4:0] rd, input [4:0] rs1, input [11:0] csr); rv_csrrw = rv_i(csr, rs1, 3'b001, rd, 7'b1110011); endfunction
function automatic [31:0] rv_csrrs(input [4:0] rd, input [4:0] rs1, input [11:0] csr); rv_csrrs = rv_i(csr, rs1, 3'b010, rd, 7'b1110011); endfunction
function automatic [31:0] rv_csrrc(input [4:0] rd, input [4:0] rs1, input [11:0] csr); rv_csrrc = rv_i(csr, rs1, 3'b011, rd, 7'b1110011); endfunction
function automatic [31:0] rv_csrr (input [4:0] rd, input [11:0] csr);                  rv_csrr  = rv_csrrs(rd, 5'd0, csr); endfunction
function automatic [31:0] rv_csrw (input [11:0] csr, input [4:0] rs1);                 rv_csrw  = rv_csrrw(5'd0, rs1, csr); endfunction
localparam logic [31:0] RV_ECALL = 32'h0000_0073;
localparam logic [31:0] RV_MRET  = 32'h3020_0073;
function automatic [31:0] rv_csrrwi(input [4:0] rd, input [4:0] uimm, input [11:0] csr); rv_csrrwi = rv_i(csr, uimm, 3'b101, rd, 7'b1110011); endfunction

// ---------------- F (RV32F) ----------------
localparam [2:0] RM_RNE = 3'd0, RM_RTZ = 3'd1, RM_RDN = 3'd2, RM_RUP = 3'd3, RM_RMM = 3'd4, RM_DYN = 3'd7;
function automatic [31:0] rv_fop(input [6:0] f7, input [4:0] fd, input [4:0] fs1, input [4:0] fs2, input [2:0] rm);
    rv_fop = {f7, fs2, fs1, rm, fd, 7'b1010011};
endfunction
function automatic [31:0] rv_fmadd(input [4:0] fd, input [4:0] fs1, input [4:0] fs2, input [4:0] fs3, input [2:0] rm);
    rv_fmadd = {fs3, 2'b00, fs2, fs1, rm, fd, 7'b1000011};
endfunction
function automatic [31:0] rv_flw(input [4:0] fd, input [4:0] rs1, input [11:0] imm); rv_flw = {imm, rs1, 3'b010, fd, 7'b0000111}; endfunction
function automatic [31:0] rv_fsw(input [4:0] fs2, input [4:0] rs1, input [11:0] imm);
    rv_fsw = {imm[11:5], fs2, rs1, 3'b010, imm[4:0], 7'b0100111};
endfunction
function automatic [31:0] rv_fmv_w_x(input [4:0] fd, input [4:0] rs1); rv_fmv_w_x = rv_fop(7'b1111000, fd, rs1, 5'd0, 3'b000); endfunction
function automatic [31:0] rv_fmv_x_w(input [4:0] rd, input [4:0] fs1); rv_fmv_x_w = rv_fop(7'b1110000, rd, fs1, 5'd0, 3'b000); endfunction

// ---------------- V (RVV 1.0 subset) ----------------
// vtype immediate: vma[7] vta[6] vsew[5:3] vlmul[2:0]
function automatic [10:0] rv_vtype(input [2:0] vsew); rv_vtype = {3'b000, 1'b0, 1'b0, vsew, 3'b000}; endfunction
function automatic [31:0] rv_vsetvli(input [4:0] rd, input [4:0] rs1, input [10:0] vtypei);
    rv_vsetvli = {1'b0, vtypei, rs1, 3'b111, rd, 7'b1010111};
endfunction
function automatic [31:0] rv_vsetivli(input [4:0] rd, input [4:0] uimm, input [9:0] vtypei);
    rv_vsetivli = {2'b11, vtypei, uimm, 3'b111, rd, 7'b1010111};
endfunction
// width: 3'b000 = e8, 3'b101 = e16, 3'b110 = e32
function automatic [31:0] rv_vle(input [2:0] width, input [4:0] vd, input [4:0] rs1, input vm);
    rv_vle = {3'b000, 1'b0, 2'b00, vm, 5'b00000, rs1, width, vd, 7'b0000111};
endfunction
function automatic [31:0] rv_vse(input [2:0] width, input [4:0] vs3, input [4:0] rs1, input vm);
    rv_vse = {3'b000, 1'b0, 2'b00, vm, 5'b00000, rs1, width, vs3, 7'b0100111};
endfunction
// funct3: 000 OPIVV, 010 OPMVV, 011 OPIVI, 100 OPIVX, 110 OPMVX
function automatic [31:0] rv_vop(input [5:0] f6, input vm, input [4:0] vd, input [4:0] vs2, input [4:0] vs1_rs1_imm, input [2:0] f3);
    rv_vop = {f6, vm, vs2, vs1_rs1_imm, f3, vd, 7'b1010111};
endfunction
