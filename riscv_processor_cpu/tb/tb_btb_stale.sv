// ============================================================
//  tb_btb_stale.sv  –  Stale branch-predictor entry after code changes
//
//  A loop trains the BTB to predict "taken" for the branch at 0x8.
//  The testbench then rewrites that instruction into an ADDI (as a
//  loader or self-modifying code would) and the program executes it
//  again. The prediction is now wrong for a non-branch instruction and
//  must be corrected: execution has to continue at 0xC.
//  (Found by riscv-formal: the pipeline only checked predictions made
//  for branches and jumps.)
// ============================================================
`timescale 1ns/1ps

module tb_btb_stale;
    `include "rv_encode.svh"

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    integer errors = 0;

    task automatic check(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $error("FAIL %s: got %0d expected %0d", what, got, exp);
        end else
            $display("PASS %s = %0d", what, exp);
    endtask

    initial begin
        for (int i = 0; i < 64; i++) dut.u_imem.mem[i] = RV_NOP;
        dut.u_imem.mem[0]  = rv_addi(5'd1, 5'd0, 12'd3);
        dut.u_imem.mem[1]  = rv_addi(5'd1, 5'd1, -12'sd1);     // loop body
        dut.u_imem.mem[2]  = rv_bne (5'd1, 5'd0, -13'sd4);     // @0x8: trains BTB "taken"
        dut.u_imem.mem[3]  = rv_addi(5'd20, 5'd20, 12'd1);     // pass counter
        dut.u_imem.mem[4]  = rv_addi(5'd22, 5'd0, 12'd2);
        dut.u_imem.mem[5]  = rv_beq (5'd20, 5'd22, 13'd24);    // second pass done -> 0x2C
        // NOPs give the testbench time to rewrite mem[2] before it is fetched again
        dut.u_imem.mem[10] = rv_jal (5'd0, -21'sd32);          // back to 0x8
        dut.u_imem.mem[11] = rv_jal (5'd0, 21'd0);             // spin

        #12 rst_n = 1;
        wait (dut.u_regfile.regs[20] == 1);
        dut.u_imem.mem[2] = rv_addi(5'd21, 5'd21, 12'd1);      // the branch becomes an ADDI
        repeat (100) @(posedge clk);

        check("rewritten instruction executed once (x21)", dut.u_regfile.regs[21], 1);
        check("loop counter untouched by wrong path (x1)", dut.u_regfile.regs[1], 0);
        check("second pass reached its end (x20)",         dut.u_regfile.regs[20], 2);

        if (errors == 0) $display("All checks passed - stale BTB entry.");
        else             $display("stale BTB entry FAILED: %0d errors", errors);
        $finish;
    end
endmodule
