// ============================================================
//  tb_phase6_control.sv  – Phase 6: Control Flow Deep Tests
//  BNE, BLT, BGE, BLTU, BGEU, backward loop, JAL+JALR chain
// ============================================================
`timescale 1ns/1ps
module tb_phase6_control;
    logic        clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top #(.IMEM_FILE("")) dut (
        .clk(clk), .rst_n(rst_n), .ext_interrupt(ext_interrupt),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    function automatic logic [31:0] f_addi(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_addi = {imm, rs1, 3'b000, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_bne(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] off);
        logic [12:1] o; o = off[12:1];
        f_bne = {o[12], o[10:5], rs2, rs1, 3'b001, o[4:1], o[11], 7'b1100011}; endfunction
    function automatic logic [31:0] f_blt(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] off);
        logic [12:1] o; o = off[12:1];
        f_blt = {o[12], o[10:5], rs2, rs1, 3'b100, o[4:1], o[11], 7'b1100011}; endfunction
    function automatic logic [31:0] f_bge(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] off);
        logic [12:1] o; o = off[12:1];
        f_bge = {o[12], o[10:5], rs2, rs1, 3'b101, o[4:1], o[11], 7'b1100011}; endfunction
    function automatic logic [31:0] f_bltu(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] off);
        logic [12:1] o; o = off[12:1];
        f_bltu = {o[12], o[10:5], rs2, rs1, 3'b110, o[4:1], o[11], 7'b1100011}; endfunction
    function automatic logic [31:0] f_bgeu(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] off);
        logic [12:1] o; o = off[12:1];
        f_bgeu = {o[12], o[10:5], rs2, rs1, 3'b111, o[4:1], o[11], 7'b1100011}; endfunction
    function automatic logic [31:0] f_jal(input logic [4:0] rd, input logic [20:0] off);
        logic [20:1] o; o = off[20:1];
        f_jal = {o[20], o[10:1], o[11], o[19:12], rd, 7'b1101111}; endfunction
    function automatic logic [31:0] f_jalr(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_jalr = {imm, rs1, 3'b000, rd, 7'b1100111}; endfunction
    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        // Test 1: BNE taken (5 != 6)
        // word [0..6]
        dut.u_imem.mem[0]  = f_addi(5'd1, 5'd0, 12'd5);
        dut.u_imem.mem[1]  = f_addi(5'd2, 5'd0, 12'd6);
        dut.u_imem.mem[2]  = f_bne (5'd1, 5'd2, 13'sh010);  // +16 → word 6
        dut.u_imem.mem[3]  = f_addi(5'd3, 5'd0, 12'd99);    // SKIPPED
        dut.u_imem.mem[4]  = f_addi(5'd3, 5'd0, 12'd99);    // SKIPPED
        dut.u_imem.mem[5]  = f_addi(5'd3, 5'd0, 12'd99);    // SKIPPED
        dut.u_imem.mem[6]  = f_addi(5'd3, 5'd0, 12'd10);    // x3=10

        // Test 2: BLT signed (-1 < 1)
        // word [7..12]
        dut.u_imem.mem[7]  = f_addi(5'd4, 5'd0, 12'hFFF);   // x4=-1
        dut.u_imem.mem[8]  = f_addi(5'd5, 5'd0, 12'd1);     // x5=1
        dut.u_imem.mem[9]  = f_blt (5'd4, 5'd5, 13'sh00C);  // +12 → word 12
        dut.u_imem.mem[10] = f_addi(5'd6, 5'd0, 12'd99);    // SKIPPED
        dut.u_imem.mem[11] = f_addi(5'd6, 5'd0, 12'd99);    // SKIPPED
        dut.u_imem.mem[12] = f_addi(5'd6, 5'd0, 12'd20);    // x6=20

        // Test 3: BGE not taken (-1 >= 1 false → fall-through)
        // word [13..15]
        dut.u_imem.mem[13] = f_bge (5'd4, 5'd5, 13'sh010);  // NOT taken
        dut.u_imem.mem[14] = f_addi(5'd7, 5'd0, 12'd30);    // x7=30 (executed)
        dut.u_imem.mem[15] = NOP;

        // Test 4: BLTU not taken (0xFFFF_FFFF >= 1 unsigned → fall-through)
        // word [16..18]
        dut.u_imem.mem[16] = f_bltu(5'd4, 5'd5, 13'sh008);  // NOT taken
        dut.u_imem.mem[17] = f_addi(5'd8, 5'd0, 12'd40);    // x8=40 (executed)
        dut.u_imem.mem[18] = NOP;

        // Test 5: BGEU taken (0xFFFF_FFFF >= 1 unsigned)
        // word [19..21]
        dut.u_imem.mem[19] = f_bgeu(5'd4, 5'd5, 13'sh008);  // +8 → word 21
        dut.u_imem.mem[20] = f_addi(5'd9, 5'd0, 12'd99);    // SKIPPED
        dut.u_imem.mem[21] = f_addi(5'd9, 5'd0, 12'd50);    // x9=50

        // Test 6: Backward branch loop (count down from 3)
        // word [22..27]
        dut.u_imem.mem[22] = f_addi(5'd10, 5'd0, 12'd3);    // x10=3
        dut.u_imem.mem[23] = f_addi(5'd11, 5'd0, 12'd0);    // x11=0 (count)
        // loop_top = word 24, byte 0x60
        dut.u_imem.mem[24] = f_addi(5'd10, 5'd10, 12'hFFF); // x10-- (add -1)
        dut.u_imem.mem[25] = f_addi(5'd11, 5'd11, 12'd1);   // x11++
        // BNE x10, x0, -8 bytes → back to word 24
        // -8 bytes in 13-bit signed = 13'b1_1111_1111_1000 = 13'h1FF8
        dut.u_imem.mem[26] = f_bne (5'd10, 5'd0, 13'b1_1111_1111_1000); // off=-8
        dut.u_imem.mem[27] = NOP;

        // Test 7: JAL forward then JALR back
        // word [28] at byte 0x70: JAL x12, +40 bytes → 0x70+0x28=0x98 → word 38
        dut.u_imem.mem[28] = f_jal (5'd12, 21'sh028);       // x12 = 0x74 (PC+4)
        dut.u_imem.mem[29] = f_addi(5'd13, 5'd0, 12'd99);   // SKIPPED (JAL skip)
        for (int i = 30; i < 38; i++) dut.u_imem.mem[i] = NOP;  // padding
        // JAL target at word 38 = byte 0x98:
        dut.u_imem.mem[38] = f_addi(5'd13, 5'd0, 12'd60);   // x13=60
        dut.u_imem.mem[39] = NOP;
        dut.u_imem.mem[40] = NOP;
        dut.u_imem.mem[41] = NOP;
        dut.u_imem.mem[42] = NOP;
    end

    initial clk = 0;
    always #5 clk = ~clk;
    integer cycle;
    initial begin
        $dumpfile("cpu_phase6_control_wave.vcd");
        $dumpvars(0, tb_phase6_control);
        rst_n = 0; ext_interrupt = 0; cycle = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(400) @(posedge clk);

        $display("=== Phase 6: Control Flow Deep Tests ===");

        if (dut.u_regfile.regs[3]  !== 32'd10) $error("FAIL x3 BNE taken: got %0d", dut.u_regfile.regs[3]);
        else $display("PASS x3 BNE taken = %0d", dut.u_regfile.regs[3]);

        if (dut.u_regfile.regs[6]  !== 32'd20) $error("FAIL x6 BLT signed taken: got %0d", dut.u_regfile.regs[6]);
        else $display("PASS x6 BLT(-1<1) taken = %0d", dut.u_regfile.regs[6]);

        if (dut.u_regfile.regs[7]  !== 32'd30) $error("FAIL x7 BGE not-taken: got %0d", dut.u_regfile.regs[7]);
        else $display("PASS x7 BGE not-taken fall-through = %0d", dut.u_regfile.regs[7]);

        if (dut.u_regfile.regs[8]  !== 32'd40) $error("FAIL x8 BLTU not-taken: got %0d", dut.u_regfile.regs[8]);
        else $display("PASS x8 BLTU not-taken fall-through = %0d", dut.u_regfile.regs[8]);

        if (dut.u_regfile.regs[9]  !== 32'd50) $error("FAIL x9 BGEU taken: got %0d", dut.u_regfile.regs[9]);
        else $display("PASS x9 BGEU(unsigned) taken = %0d", dut.u_regfile.regs[9]);

        if (dut.u_regfile.regs[10] !== 32'd0) $error("FAIL x10 loop end: got %0d", dut.u_regfile.regs[10]);
        else $display("PASS x10 backward-branch loop end = %0d", dut.u_regfile.regs[10]);

        if (dut.u_regfile.regs[11] !== 32'd3) $error("FAIL x11 loop count: got %0d", dut.u_regfile.regs[11]);
        else $display("PASS x11 backward-branch count = %0d", dut.u_regfile.regs[11]);

        if (dut.u_regfile.regs[13] !== 32'd60) $error("FAIL x13 JAL target: got %0d", dut.u_regfile.regs[13]);
        else $display("PASS x13 JAL forward target = %0d", dut.u_regfile.regs[13]);

        $display("");
        $display("Phase 6 Control Flow Tests: ALL CHECKS DONE");
        $finish;
    end
    always @(posedge clk) if (rst_n) $display("CY%2d | PC=%08h", cycle++, dbg_pc);
endmodule
