// ============================================================
//  tb_phase6_alu.sv  – Phase 6: ALU & Memory Corner Cases
//  Tests: overflow, SRA/SRL/SLL extremes, SLT/SLTU edge cases,
//         AUIPC, LUI, byte/half loads with sign-extension
// ============================================================
`timescale 1ns/1ps
module tb_phase6_alu;
    logic        clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top #(.IMEM_FILE("")) dut (
        .clk(clk), .rst_n(rst_n), .ext_interrupt(ext_interrupt),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    // Icarus-compatible function signatures (no ';' separator)
    function automatic logic [31:0] f_addi(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_addi = {imm, rs1, 3'b000, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_add(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        f_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
    function automatic logic [31:0] f_sub(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        f_sub = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
    function automatic logic [31:0] f_slli(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] shamt);
        f_slli = {7'b0000000, shamt, rs1, 3'b001, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_srli(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] shamt);
        f_srli = {7'b0000000, shamt, rs1, 3'b101, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_srai(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] shamt);
        f_srai = {7'b0100000, shamt, rs1, 3'b101, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_slti(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_slti = {imm, rs1, 3'b010, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_sltiu(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_sltiu = {imm, rs1, 3'b011, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_xori(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_xori = {imm, rs1, 3'b100, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_lui(input logic [4:0] rd, input logic [19:0] imm20);
        f_lui = {imm20, rd, 7'b0110111}; endfunction
    function automatic logic [31:0] f_auipc(input logic [4:0] rd, input logic [19:0] imm20);
        f_auipc = {imm20, rd, 7'b0010111}; endfunction
    function automatic logic [31:0] f_sw(input logic [4:0] rs1, input logic [4:0] rs2, input logic [11:0] imm);
        f_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}; endfunction
    function automatic logic [31:0] f_sh(input logic [4:0] rs1, input logic [4:0] rs2, input logic [11:0] imm);
        f_sh = {imm[11:5], rs2, rs1, 3'b001, imm[4:0], 7'b0100011}; endfunction
    function automatic logic [31:0] f_sb(input logic [4:0] rs1, input logic [4:0] rs2, input logic [11:0] imm);
        f_sb = {imm[11:5], rs2, rs1, 3'b000, imm[4:0], 7'b0100011}; endfunction
    function automatic logic [31:0] f_lw(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_lw = {imm, rs1, 3'b010, rd, 7'b0000011}; endfunction
    function automatic logic [31:0] f_lh(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_lh = {imm, rs1, 3'b001, rd, 7'b0000011}; endfunction
    function automatic logic [31:0] f_lhu(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_lhu = {imm, rs1, 3'b101, rd, 7'b0000011}; endfunction
    function automatic logic [31:0] f_lb(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_lb = {imm, rs1, 3'b000, rd, 7'b0000011}; endfunction
    function automatic logic [31:0] f_lbu(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_lbu = {imm, rs1, 3'b100, rd, 7'b0000011}; endfunction
    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        // x1 = 0x7FFF_FFFF: use all-ones then clear sign bit
        // x1 = -1 (addi x1, x0, -1) = 0xFFFF_FFFF
        dut.u_imem.mem[0]  = f_addi (5'd1, 5'd0, 12'hFFF);  // x1=-1=0xFFFF_FFFF
        // x2 = 1
        dut.u_imem.mem[1]  = f_addi (5'd2, 5'd0, 12'd1);    // x2=1
        // x1 = x1 XOR 0x80000000 → clear bit31 → 0x7FFF_FFFF
        // Use: srli x1, x1, 1 = logical right shift → 0x7FFF_FFFF
        dut.u_imem.mem[2]  = f_srli (5'd1, 5'd1, 5'd1);     // x1 = 0x7FFF_FFFF
        // x3 = x1+x2 overflows to 0x8000_0000
        dut.u_imem.mem[3]  = f_add  (5'd3, 5'd1, 5'd2);     // x3=0x8000_0000
        // x4 = x1 - x2 = 0x7FFF_FFFE
        dut.u_imem.mem[4]  = f_sub  (5'd4, 5'd1, 5'd2);     // x4=0x7FFF_FFFE
        // x5 = -1 (addi x5, x0, -1)
        dut.u_imem.mem[5]  = f_addi (5'd5, 5'd0, 12'hFFF);  // x5=0xFFFF_FFFF
        // x6 = SRA(x5, 4) → 0xFFFF_FFFF (arithmetic right shift of all-ones)
        dut.u_imem.mem[6]  = f_srai (5'd6, 5'd5, 5'd4);
        // x7 = SRL(x5, 4) → 0x0FFF_FFFF (logical)
        dut.u_imem.mem[7]  = f_srli (5'd7, 5'd5, 5'd4);
        // x8 = SLL(x2, 31) → 0x8000_0000
        dut.u_imem.mem[8]  = f_slli (5'd8, 5'd2, 5'd31);
        // x9 = SLTI(x5, 0) → 1 (x5=-1 < 0 signed)
        dut.u_imem.mem[9]  = f_slti (5'd9, 5'd5, 12'd0);
        // x10 = SLTIU(x5, 1) → 0 (0xFFFF_FFFF >= 1 unsigned)
        dut.u_imem.mem[10] = f_sltiu(5'd10, 5'd5, 12'd1);
        // x11 = XORI(x5, 0xABC) → 0xFFFF_F543
        dut.u_imem.mem[11] = f_xori (5'd11, 5'd5, 12'hABC);
        // x12 = LUI 0xDEAD0 → 0xDEAD_0000
        dut.u_imem.mem[12] = f_lui  (5'd12, 20'hDEAD0);
        // x13 = AUIPC at word 13 = PC 0x34, imm=0x1 → 0x34+0x1000=0x1034
        dut.u_imem.mem[13] = f_auipc(5'd13, 20'h00001);

        // Byte/halfword store-load roundtrip
        dut.u_imem.mem[14] = f_addi (5'd20, 5'd0, 12'h200);       // x20=0x200 base
        dut.u_imem.mem[15] = f_addi (5'd21, 5'd0, 12'hFFF);       // x21=-1
        // SB and LB/LBU
        dut.u_imem.mem[16] = f_sb   (5'd20, 5'd21, 12'h0);        // mem[0x200]=0xFF
        dut.u_imem.mem[17] = f_lb   (5'd22, 5'd20, 12'h0);        // x22=0xFFFF_FFFF (sign-ext)
        dut.u_imem.mem[18] = f_lbu  (5'd23, 5'd20, 12'h0);        // x23=0x0000_00FF (zero-ext)
        // SH and LH/LHU with positive value
        dut.u_imem.mem[19] = f_addi (5'd24, 5'd0, 12'h204);
        dut.u_imem.mem[20] = f_addi (5'd25, 5'd0, 12'h7FF);       // 0x7FF
        dut.u_imem.mem[21] = f_sh   (5'd24, 5'd25, 12'h0);
        dut.u_imem.mem[22] = f_lh   (5'd26, 5'd24, 12'h0);        // x26=0x0000_07FF
        dut.u_imem.mem[23] = f_lhu  (5'd27, 5'd24, 12'h0);        // x27=0x0000_07FF
        // SH and LH with negative value (sign ext)
        dut.u_imem.mem[24] = f_addi (5'd28, 5'd0, 12'h208);
        dut.u_imem.mem[25] = f_sh   (5'd28, 5'd21, 12'h0);        // store 0xFFFF (x21=-1)
        dut.u_imem.mem[26] = f_lh   (5'd30, 5'd28, 12'h0);        // x30=0xFFFF_FFFF
        dut.u_imem.mem[27] = f_lhu  (5'd31, 5'd28, 12'h0);        // x31=0x0000_FFFF
        dut.u_imem.mem[28] = NOP;
        dut.u_imem.mem[29] = NOP;
    end

    initial clk = 0;
    always #5 clk = ~clk;
    integer cycle;
    initial begin
        $dumpfile("cpu_phase6_alu_wave.vcd");
        $dumpvars(0, tb_phase6_alu);
        rst_n = 0; ext_interrupt = 0; cycle = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(100) @(posedge clk);

        $display("=== Phase 6: ALU & Memory Corner Cases ===");

        if (dut.u_regfile.regs[3]  !== 32'h8000_0000) $error("FAIL x3 overflow-add: got 0x%08h", dut.u_regfile.regs[3]);
        else $display("PASS x3 overflow-add = 0x%08h", dut.u_regfile.regs[3]);

        if (dut.u_regfile.regs[4]  !== 32'h7FFF_FFFE) $error("FAIL x4 sub: got 0x%08h", dut.u_regfile.regs[4]);
        else $display("PASS x4 sub = 0x%08h", dut.u_regfile.regs[4]);

        if (dut.u_regfile.regs[6]  !== 32'hFFFF_FFFF) $error("FAIL x6 SRA(-1,4): got 0x%08h", dut.u_regfile.regs[6]);
        else $display("PASS x6 SRA(-1,4) = 0x%08h", dut.u_regfile.regs[6]);

        if (dut.u_regfile.regs[7]  !== 32'h0FFF_FFFF) $error("FAIL x7 SRL(-1,4): got 0x%08h", dut.u_regfile.regs[7]);
        else $display("PASS x7 SRL(-1,4) = 0x%08h", dut.u_regfile.regs[7]);

        if (dut.u_regfile.regs[8]  !== 32'h8000_0000) $error("FAIL x8 SLL(1,31): got 0x%08h", dut.u_regfile.regs[8]);
        else $display("PASS x8 SLL(1,31) = 0x%08h", dut.u_regfile.regs[8]);

        if (dut.u_regfile.regs[9]  !== 32'd1) $error("FAIL x9 SLTI(-1<0): got %0d", dut.u_regfile.regs[9]);
        else $display("PASS x9 SLTI(-1<0) = %0d", dut.u_regfile.regs[9]);

        if (dut.u_regfile.regs[10] !== 32'd0) $error("FAIL x10 SLTIU: got %0d", dut.u_regfile.regs[10]);
        else $display("PASS x10 SLTIU(0xFFFF>=1) = %0d", dut.u_regfile.regs[10]);

        if (dut.u_regfile.regs[12] !== 32'hDEAD_0000) $error("FAIL x12 LUI: got 0x%08h", dut.u_regfile.regs[12]);
        else $display("PASS x12 LUI = 0x%08h", dut.u_regfile.regs[12]);

        if (dut.u_regfile.regs[13] !== 32'h0000_1034) $error("FAIL x13 AUIPC: got 0x%08h", dut.u_regfile.regs[13]);
        else $display("PASS x13 AUIPC = 0x%08h", dut.u_regfile.regs[13]);

        if (dut.u_regfile.regs[22] !== 32'hFFFF_FFFF) $error("FAIL x22 LB sign-ext: got 0x%08h", dut.u_regfile.regs[22]);
        else $display("PASS x22 LB(0xFF) sign-ext = 0x%08h", dut.u_regfile.regs[22]);

        if (dut.u_regfile.regs[23] !== 32'h0000_00FF) $error("FAIL x23 LBU zero-ext: got 0x%08h", dut.u_regfile.regs[23]);
        else $display("PASS x23 LBU(0xFF) zero-ext = 0x%08h", dut.u_regfile.regs[23]);

        if (dut.u_regfile.regs[26] !== 32'h0000_07FF) $error("FAIL x26 LH pos: got 0x%08h", dut.u_regfile.regs[26]);
        else $display("PASS x26 LH(0x7FF) = 0x%08h", dut.u_regfile.regs[26]);

        if (dut.u_regfile.regs[30] !== 32'hFFFF_FFFF) $error("FAIL x30 LH neg sign-ext: got 0x%08h", dut.u_regfile.regs[30]);
        else $display("PASS x30 LH(-1) sign-ext = 0x%08h", dut.u_regfile.regs[30]);

        if (dut.u_regfile.regs[31] !== 32'h0000_FFFF) $error("FAIL x31 LHU zero-ext: got 0x%08h", dut.u_regfile.regs[31]);
        else $display("PASS x31 LHU(0xFFFF) zero-ext = 0x%08h", dut.u_regfile.regs[31]);

        $display("");
        $display("Phase 6 ALU Corner Cases: ALL CHECKS DONE");
        $finish;
    end
    always @(posedge clk) if (rst_n) $display("CY%2d | PC=%08h", cycle++, dbg_pc);
endmodule
