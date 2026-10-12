// ============================================================
//  tb_vector.sv  –  RVV 1.0 subset through the pipeline
//
//  Real RVV encodings: vsetvli/vsetivli, vle/vse (e8/e16/e32),
//  .vv/.vx/.vi arithmetic, vmul, vredsum, vmv.x.s, compare -> mask,
//  masked execution, tail-undisturbed stores with vl < VLMAX, and the
//  traps for vill, read-only vl, EEW != SEW and misaligned accesses.
// ============================================================
`timescale 1ns/1ps

module tb_vector;
    `include "rv_encode.svh"

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    localparam logic [11:0] MTVEC = 12'h305, MEPC = 12'h341, MCAUSE = 12'h342,
                            VL = 12'hC20, VTYPE = 12'hC21, VLENB = 12'hC22;
    localparam [2:0] OPIVV = 3'b000, OPMVV = 3'b010, OPIVI = 3'b011, OPIVX = 3'b100, OPMVX = 3'b110;
    localparam [2:0] E8 = 3'b000, E16 = 3'b101, E32 = 3'b110;

    `define DMEM dut.u_dcache.u_l2.u_dram.u_dmem.mem
    `define VREG dut.g_vec_regs.u_vec_regfile.regs
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
        logic [9:0] e32_10, e16_10;
        e32_10 = rv_vtype(3'd2);
        e16_10 = rv_vtype(3'd1);

        for (int i = 0; i < 256; i++) dut.u_imem.mem[i] = RV_NOP;
        for (int i = 64; i < 200; i++) `DMEM[i] = 32'h0;
        `DMEM[64] = 1;  `DMEM[65] = 2;  `DMEM[66] = 3;  `DMEM[67] = 4;    // A @0x100
        `DMEM[80] = 10; `DMEM[81] = 20; `DMEM[82] = 30; `DMEM[83] = 40;   // B @0x140
        `DMEM[147] = 32'hDEAD_BEEF;                                        // tail sentinel

        dut.u_imem.mem[0]  = rv_addi(5'd1, 5'd0, 12'h200);
        dut.u_imem.mem[1]  = rv_csrw(MTVEC, 5'd1);
        dut.u_imem.mem[2]  = rv_addi(5'd27, 5'd0, 12'h300);
        dut.u_imem.mem[3]  = rv_vop(6'b000000, 1'b1, 5'd3, 5'd2, 5'd1, OPIVV);  // vill after reset: trap (r0)
        dut.u_imem.mem[4]  = rv_vsetivli(5'd5, 5'd4, e32_10);                  // vl = 4, e32
        dut.u_imem.mem[5]  = rv_addi(5'd2, 5'd0, 12'h100);
        dut.u_imem.mem[6]  = rv_vle(E32, 5'd1, 5'd2, 1'b1);                    // v1 = A
        dut.u_imem.mem[7]  = rv_addi(5'd3, 5'd0, 12'h140);
        dut.u_imem.mem[8]  = rv_vle(E32, 5'd2, 5'd3, 1'b1);                    // v2 = B
        dut.u_imem.mem[9]  = rv_vop(6'b000000, 1'b1, 5'd3, 5'd2, 5'd1, OPIVV); // vadd.vv v3 = B + A
        dut.u_imem.mem[10] = rv_addi(5'd4, 5'd0, 12'h180);
        dut.u_imem.mem[11] = rv_vse(E32, 5'd3, 5'd4, 1'b1);
        dut.u_imem.mem[12] = rv_addi(5'd6, 5'd0, 12'd3);
        dut.u_imem.mem[13] = rv_vop(6'b100101, 1'b1, 5'd4, 5'd1, 5'd6, OPMVX); // vmul.vx v4 = A * 3
        dut.u_imem.mem[14] = rv_addi(5'd7, 5'd0, 12'h1C0);
        dut.u_imem.mem[15] = rv_vse(E32, 5'd4, 5'd7, 1'b1);
        dut.u_imem.mem[16] = rv_vop(6'b000000, 1'b1, 5'd5, 5'd2, 5'd1, OPMVV); // vredsum.vs v5 = A[0] + sum(B)
        dut.u_imem.mem[17] = rv_vop(6'b010000, 1'b1, 5'd8, 5'd5, 5'd0, OPMVV); // vmv.x.s x8 = v5[0]
        dut.u_imem.mem[18] = rv_vop(6'b011011, 1'b1, 5'd0, 5'd1, 5'd6, OPIVX); // vmslt.vx v0 = A < 3
        dut.u_imem.mem[19] = rv_vop(6'b000000, 1'b0, 5'd6, 5'd2, 5'd1, OPIVI); // vadd.vi v6 = B + 1, v0.t
        dut.u_imem.mem[20] = rv_addi(5'd9, 5'd0, 12'h200);
        dut.u_imem.mem[21] = rv_vse(E32, 5'd6, 5'd9, 1'b1);
        dut.u_imem.mem[22] = rv_vsetivli(5'd10, 5'd3, e32_10);                 // vl = 3
        dut.u_imem.mem[23] = rv_vop(6'b000010, 1'b1, 5'd7, 5'd2, 5'd1, OPIVV); // vsub.vv v7 = B - A
        dut.u_imem.mem[24] = rv_addi(5'd11, 5'd0, 12'h240);
        dut.u_imem.mem[25] = rv_vse(E32, 5'd7, 5'd11, 1'b1);                   // stores only 3 elements
        dut.u_imem.mem[26] = rv_addi(5'd12, 5'd0, 12'd16);
        dut.u_imem.mem[27] = rv_vsetvli(5'd13, 5'd12, rv_vtype(3'd0));         // e8, vl = 16
        dut.u_imem.mem[28] = rv_vle(E8, 5'd8, 5'd2, 1'b1);                     // 16 bytes of A
        dut.u_imem.mem[29] = rv_addi(5'd14, 5'd0, 12'd5);
        dut.u_imem.mem[30] = rv_vop(6'b000000, 1'b1, 5'd9, 5'd8, 5'd14, OPIVX);// vadd.vx (bytes + 5)
        dut.u_imem.mem[31] = rv_addi(5'd15, 5'd0, 12'h280);
        dut.u_imem.mem[32] = rv_vse(E8, 5'd9, 5'd15, 1'b1);
        dut.u_imem.mem[33] = rv_vsetvli(5'd16, 5'd0, rv_vtype(3'd3));          // e64 unsupported: vill, vl = 0
        dut.u_imem.mem[34] = rv_csrr(5'd17, VTYPE);
        dut.u_imem.mem[35] = rv_vop(6'b000000, 1'b1, 5'd10, 5'd2, 5'd1, OPIVV);// vill: trap (r1)
        dut.u_imem.mem[36] = rv_csrr(5'd18, VLENB);
        dut.u_imem.mem[37] = rv_csrw(VL, 5'd12);                               // vl is read-only: trap (r2)
        dut.u_imem.mem[38] = rv_vsetivli(5'd19, 5'd2, e16_10);                 // e16, vl = 2
        dut.u_imem.mem[39] = rv_vle(E32, 5'd11, 5'd2, 1'b1);                   // EEW != SEW: trap (r3)
        dut.u_imem.mem[40] = rv_addi(5'd20, 5'd0, 12'h102);
        dut.u_imem.mem[41] = rv_vle(E16, 5'd12, 5'd20, 1'b1);                  // halfwords at 0x102, 0x104
        dut.u_imem.mem[42] = rv_addi(5'd21, 5'd0, 12'h101);
        dut.u_imem.mem[43] = rv_vle(E16, 5'd13, 5'd21, 1'b1);                  // misaligned: trap (r4)
        dut.u_imem.mem[44] = rv_jal(5'd0, 21'd0);
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
        repeat (700) @(posedge clk);

        check("vill at reset traps (mcause)", `DMEM[192], 32'd2);
        check("vill at reset traps (mepc)",   `DMEM[193], 32'h0C);
        check("vsetivli vl=4",                `XREG[5], 32'd4);
        for (int i = 0; i < 4; i++) check($sformatf("vadd.vv elem %0d", i), `DMEM[96 + i], 11 * (i + 1));
        for (int i = 0; i < 4; i++) check($sformatf("vmul.vx elem %0d", i), `DMEM[112 + i], 3 * (i + 1));
        check("vredsum + vmv.x.s",            `XREG[8], 32'd101);
        check("vmslt mask bits",              {28'd0, `VREG[0][3:0]}, 32'h3);
        check("masked vadd elem 0",           `DMEM[128], 32'd11);
        check("masked vadd elem 1",           `DMEM[129], 32'd21);
        check("masked-off elem 2 undisturbed",`DMEM[130], 32'd0);
        check("masked-off elem 3 undisturbed",`DMEM[131], 32'd0);
        check("vsetivli vl=3",                `XREG[10], 32'd3);
        for (int i = 0; i < 3; i++) check($sformatf("vsub.vv elem %0d", i), `DMEM[144 + i], 9 * (i + 1));
        check("store past vl untouched",      `DMEM[147], 32'hDEAD_BEEF);
        check("vsetvli e8 vl=16",             `XREG[13], 32'd16);
        for (int i = 0; i < 4; i++) check($sformatf("e8 vadd.vx word %0d", i), `DMEM[160 + i], 32'h0505_0506 + i);
        check("unsupported SEW gives vl=0",   `XREG[16], 32'd0);
        check("vtype.vill set",               `XREG[17], 32'h8000_0000);
        check("vill instruction traps",       `DMEM[194], 32'd2);
        check("vill instruction mepc",        `DMEM[195], 32'h8C);
        check("vlenb",                        `XREG[18], 32'd16);
        check("csrw vl traps",                `DMEM[196], 32'd2);
        check("csrw vl mepc",                 `DMEM[197], 32'h94);
        check("vsetivli e16 vl=2",            `XREG[19], 32'd2);
        check("EEW != SEW traps",             `DMEM[198], 32'd2);
        check("EEW != SEW mepc",              `DMEM[199], 32'h9C);
        check("vle16 from 0x102",             `VREG[12][31:0], 32'h0002_0000);
        check("misaligned vle16 cause",       `DMEM[200], 32'd4);
        check("misaligned vle16 mepc",        `DMEM[201], 32'hAC);

        if (errors == 0) $display("All checks passed - vector integration.");
        else             $display("vector integration FAILED: %0d errors", errors);
        $finish;
    end
endmodule
