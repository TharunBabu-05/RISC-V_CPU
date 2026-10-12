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
