// ============================================================
//  tb_mem_stall.sv  –  Pipeline control during a D-cache miss
//
//  While a load misses in MEM the pipeline is frozen. Instructions
//  held in EX/ID during that freeze must not be lost:
//    1. a taken branch in EX must still redirect fetch
//    2. a load in EX with a dependent instruction in ID (load-use)
//       must still execute
// ============================================================
`timescale 1ns/1ps

module tb_mem_stall;
    `include "rv_encode.svh"

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    `define DMEM dut.u_dcache.u_l2.u_dram.u_dmem.mem
    integer errors = 0;

    task automatic check(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $error("FAIL %s: got %h expected %h", what, got, exp);
        end else
            $display("PASS %s = %h", what, exp);
    endtask

    initial begin
        for (int i = 0; i < 64; i++) dut.u_imem.mem[i] = RV_NOP;
        `DMEM[64]  = 32'h55;   // 0x100
        `DMEM[96]  = 32'h66;   // 0x180
        `DMEM[112] = 32'h77;   // 0x1C0

        dut.u_imem.mem[0] = rv_addi(5'd1, 5'd0, 12'd1);
        dut.u_imem.mem[1] = rv_lw  (5'd2, 5'd0, 12'h100);     // cache miss in MEM ...
        dut.u_imem.mem[2] = rv_beq (5'd0, 5'd0, 13'd12);      // ... while this taken branch is in EX
        dut.u_imem.mem[3] = rv_addi(5'd5, 5'd0, 12'd99);      // must be skipped
        dut.u_imem.mem[4] = rv_addi(5'd6, 5'd0, 12'd99);      // must be skipped
        dut.u_imem.mem[5] = rv_addi(5'd7, 5'd0, 12'd7);
        dut.u_imem.mem[6] = rv_lw  (5'd8, 5'd0, 12'h180);     // cache miss in MEM ...
        dut.u_imem.mem[7] = rv_lw  (5'd9, 5'd0, 12'h1C0);     // ... while this load is in EX
        dut.u_imem.mem[8] = rv_addi(5'd10, 5'd9, 12'd1);      // ... and this load-use is in ID
        dut.u_imem.mem[9] = rv_jal (5'd0, 21'd0);

        #12 rst_n = 1;
        repeat (100) @(posedge clk);

        check("load before branch (x2)",    dut.u_regfile.regs[2],  32'h55);
        check("branch shadow 1 skipped (x5)", dut.u_regfile.regs[5], 32'h0);
        check("branch shadow 2 skipped (x6)", dut.u_regfile.regs[6], 32'h0);
        check("branch target (x7)",         dut.u_regfile.regs[7],  32'h7);
        check("missing load (x8)",          dut.u_regfile.regs[8],  32'h66);
        check("load held in EX (x9)",       dut.u_regfile.regs[9],  32'h77);
        check("load-use consumer (x10)",    dut.u_regfile.regs[10], 32'h78);

        if (errors == 0) $display("All checks passed - stalls during cache miss.");
        else             $display("stalls during cache miss FAILED: %0d errors", errors);
        $finish;
    end
endmodule
