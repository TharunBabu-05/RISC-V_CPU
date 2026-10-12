// ============================================================
//  tb_fp.sv  –  RV32F integration through the pipeline
//
//  Expected values come from tb/fpu_ref.py (bit-exact IEEE-754).
//  Covers: mstatus.FS gating, FLW/FSW, dependent FP chains (RAW
//  interlock), FMADD, FDIV/FSQRT, conversions with static and
//  dynamic rounding, compares, FCLASS, FMV, f0 being a normal
//  register, fflags accumulation, FS/SD dirty tracking, and
//  illegal rounding modes.
// ============================================================
`timescale 1ns/1ps

module tb_fp;
    `include "rv_encode.svh"

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    localparam logic [11:0] FFLAGS = 12'h001, FRM = 12'h002, MSTATUS = 12'h300, MTVEC = 12'h305,
                            MEPC = 12'h341, MCAUSE = 12'h342;
    // OP-FP funct7 values
    localparam logic [6:0] FADD = 7'b0000000, FSUB = 7'b0000100, FMUL = 7'b0001000, FDIV = 7'b0001100,
                           FSQRT = 7'b0101100, FCMP = 7'b1010000, FCLASS = 7'b1110000,
                           FCVT_W_S = 7'b1100000, FCVT_S_W = 7'b1101000;

    `define DMEM dut.u_dcache.u_l2.u_dram.u_dmem.mem
    `define FREG dut.g_fp_regs.u_fp_regfile.regs
    `define XREG dut.u_regfile.regs
    integer errors = 0;

    task automatic check(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $error("FAIL %s: got %h expected %h", what, got, exp);
        end else
            $display("PASS %s = %h", what, exp);
    endtask

    initial begin
        for (int i = 0; i < 256; i++) dut.u_imem.mem[i] = RV_NOP;
        `DMEM[32] = 32'h3FC0_0000;    // 0x80: 1.5
        `DMEM[33] = 32'h4010_0000;    // 0x84: 2.25
        `DMEM[34] = 32'hBDCC_CCCD;    // 0x88: -0.1
        `DMEM[35] = 32'hFFFF_FFFD;    // 0x8C: -3
        for (int i = 192; i < 200; i++) `DMEM[i] = 32'h0;

        dut.u_imem.mem[0]  = rv_addi(5'd1, 5'd0, 12'h200);
        dut.u_imem.mem[1]  = rv_csrw(MTVEC, 5'd1);
        dut.u_imem.mem[2]  = rv_addi(5'd27, 5'd0, 12'h300);
        dut.u_imem.mem[3]  = rv_flw(5'd1, 5'd0, 12'h80);                 // FS = Off: illegal (record 0)
        dut.u_imem.mem[4]  = rv_lui(5'd5, 20'h00002);                     // 0x2000 = FS Initial
        dut.u_imem.mem[5]  = rv_csrrs(5'd0, 5'd5, MSTATUS);
        dut.u_imem.mem[6]  = rv_flw(5'd1, 5'd0, 12'h80);                  // f1 = 1.5
        dut.u_imem.mem[7]  = rv_flw(5'd2, 5'd0, 12'h84);                  // f2 = 2.25
        dut.u_imem.mem[8]  = rv_flw(5'd3, 5'd0, 12'h88);                  // f3 = -0.1
        dut.u_imem.mem[9]  = rv_fop(FADD, 5'd4, 5'd1, 5'd2, RM_RNE);      // f4 = 3.75 (uses just-loaded regs)
        dut.u_imem.mem[10] = rv_fop(FMUL, 5'd5, 5'd1, 5'd2, RM_RNE);      // f5 = 3.375
        dut.u_imem.mem[11] = rv_fop(FADD, 5'd9, 5'd4, 5'd5, RM_RNE);      // f9 = 7.125 (back-to-back RAW)
        dut.u_imem.mem[12] = rv_fop(FDIV, 5'd6, 5'd2, 5'd1, RM_RNE);      // f6 = 1.5
        dut.u_imem.mem[13] = rv_fop(FSQRT, 5'd7, 5'd2, 5'd0, RM_RNE);     // f7 = 1.5
        dut.u_imem.mem[14] = rv_fmadd(5'd8, 5'd1, 5'd2, 5'd3, RM_RNE);    // f8 = 1.5*2.25 - 0.1 (inexact)
        dut.u_imem.mem[15] = rv_fop(FSUB, 5'd10, 5'd9, 5'd9, RM_RNE);     // f10 = +0
        dut.u_imem.mem[16] = rv_fop(FCVT_W_S, 5'd10, 5'd9, 5'd0, RM_RNE); // x10 = 7
        dut.u_imem.mem[17] = rv_fop(FCVT_W_S, 5'd11, 5'd9, 5'd0, RM_RUP); // x11 = 8
        dut.u_imem.mem[18] = rv_lw(5'd12, 5'd0, 12'h8C);                  // x12 = -3
        dut.u_imem.mem[19] = rv_fop(FCVT_S_W, 5'd11, 5'd12, 5'd0, RM_RNE);// f11 = -3.0 (integer load-use)
        dut.u_imem.mem[20] = rv_fop(FCMP, 5'd13, 5'd6, 5'd7, 3'b010);     // x13 = feq(f6, f7) = 1
        dut.u_imem.mem[21] = rv_fop(FCMP, 5'd14, 5'd3, 5'd1, 3'b001);     // x14 = flt(f3, f1) = 1
        dut.u_imem.mem[22] = rv_fop(FCLASS, 5'd15, 5'd3, 5'd0, 3'b001);   // x15 = fclass(-0.1) = 2
        dut.u_imem.mem[23] = rv_fmv_x_w(5'd16, 5'd8);                     // x16 = bits(f8)
        dut.u_imem.mem[24] = rv_fsw(5'd8, 5'd0, 12'h90);
        dut.u_imem.mem[25] = rv_flw(5'd12, 5'd0, 12'h90);
        dut.u_imem.mem[26] = rv_fop(FADD, 5'd13, 5'd12, 5'd12, RM_RNE);   // FP load-use
        dut.u_imem.mem[27] = rv_lui(5'd6, 20'h12345);
        dut.u_imem.mem[28] = rv_fmv_w_x(5'd0, 5'd6);                      // f0 is writable
        dut.u_imem.mem[29] = rv_fmv_x_w(5'd17, 5'd0);
        dut.u_imem.mem[30] = rv_fop(FDIV, 5'd14, 5'd1, 5'd20, RM_RNE);    // 1.5 / +0 -> +inf, DZ
        dut.u_imem.mem[31] = rv_csrr(5'd18, FFLAGS);
        dut.u_imem.mem[32] = rv_csrr(5'd19, MSTATUS);
        dut.u_imem.mem[33] = rv_csrrwi(5'd0, 5'd3, FRM);                  // frm = RUP
        dut.u_imem.mem[34] = rv_fop(FCVT_W_S, 5'd20, 5'd9, 5'd0, RM_DYN); // x20 = 8 (dynamic rm)
        dut.u_imem.mem[35] = rv_fop(FADD, 5'd15, 5'd1, 5'd2, 3'b101);     // reserved rm: illegal (record 1)
        dut.u_imem.mem[36] = rv_csrrwi(5'd0, 5'd5, FRM);                  // frm = 5 (invalid)
        dut.u_imem.mem[37] = rv_fop(FADD, 5'd16, 5'd1, 5'd2, RM_DYN);     // dynamic rm invalid (record 2)
        dut.u_imem.mem[38] = rv_fsw(5'd13, 5'd0, 12'h94);
        dut.u_imem.mem[39] = rv_jal(5'd0, 21'd0);
        // Trap handler @0x200: record {mcause, mepc}, skip the instruction
        dut.u_imem.mem[128] = rv_csrr(5'd28, MCAUSE);
        dut.u_imem.mem[129] = rv_sw  (5'd28, 5'd27, 12'd0);
        dut.u_imem.mem[130] = rv_csrr(5'd28, MEPC);
        dut.u_imem.mem[131] = rv_sw  (5'd28, 5'd27, 12'd4);
        dut.u_imem.mem[132] = rv_addi(5'd27, 5'd27, 12'd8);
        dut.u_imem.mem[133] = rv_addi(5'd28, 5'd28, 12'd4);
        dut.u_imem.mem[134] = rv_csrw(MEPC, 5'd28);
        dut.u_imem.mem[135] = RV_MRET;

        #12 rst_n = 1;
        repeat (500) @(posedge clk);

        check("FS-off FLW traps (mcause)",  `DMEM[192], 32'd2);
        check("FS-off FLW traps (mepc)",    `DMEM[193], 32'h0C);
        check("f4 fadd",                    `FREG[4],  32'h4070_0000);
        check("f5 fmul",                    `FREG[5],  32'h4058_0000);
        check("f9 dependent fadd",          `FREG[9],  32'h40E4_0000);
        check("f6 fdiv",                    `FREG[6],  32'h3FC0_0000);
        check("f7 fsqrt",                   `FREG[7],  32'h3FC0_0000);
        check("f8 fmadd",                   `FREG[8],  32'h4051_999A);
        check("f10 x - x = +0",             `FREG[10], 32'h0000_0000);
        check("x10 fcvt.w.s rne",           `XREG[10], 32'd7);
        check("x11 fcvt.w.s rup",           `XREG[11], 32'd8);
        check("f11 fcvt.s.w -3",            `FREG[11], 32'hC040_0000);
        check("x13 feq",                    `XREG[13], 32'd1);
        check("x14 flt",                    `XREG[14], 32'd1);
        check("x15 fclass",                 `XREG[15], 32'd2);
        check("x16 fmv.x.w",                `XREG[16], 32'h4051_999A);
        check("f13 FP load-use fadd",       `FREG[13], 32'h40D1_999A);
        check("x17 f0 is a real register",  `XREG[17], 32'h1234_5000);
        check("f14 1.5/0 = +inf",           `FREG[14], 32'h7F80_0000);
        check("fflags = DZ|NX",             `XREG[18], 32'h09);
        check("mstatus.FS dirty",           {30'd0, `XREG[19][14:13]}, 32'd3);
        check("mstatus.SD",                 {31'd0, `XREG[19][31]}, 32'd1);
        check("x20 fcvt.w.s dynamic rup",   `XREG[20], 32'd8);
        check("reserved rm traps (mcause)", `DMEM[194], 32'd2);
        check("reserved rm traps (mepc)",   `DMEM[195], 32'h8C);
        check("invalid frm traps (mcause)", `DMEM[196], 32'd2);
        check("invalid frm traps (mepc)",   `DMEM[197], 32'h94);
        check("f15 not written",            `FREG[15], 32'h0);
        check("fsw data",                   `DMEM[37], 32'h40D1_999A);

        if (errors == 0) $display("All checks passed - FP integration.");
        else             $display("FP integration FAILED: %0d errors", errors);
        $finish;
    end
endmodule
