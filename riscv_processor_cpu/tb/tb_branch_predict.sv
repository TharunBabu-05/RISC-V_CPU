// ============================================================
//  tb_branch_predict.sv  –  Branch predictor effectiveness
//
//  A 20-iteration loop plus a forward JAL. A correctly predicted
//  branch must not flush the pipeline, so only real mispredictions
//  (BTB cold misses and the loop exit) may cause a flush.
// ============================================================
`timescale 1ns/1ps

module tb_branch_predict;
    `include "rv_encode.svh"

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    localparam int ITER = 20;

    integer errors = 0, flushes = 0, cycles = 0;
    logic   done = 0;

    always @(posedge clk) if (rst_n && !done) begin
        cycles++;
        // the final spin loop (mem[8] @0x20) is not part of the measurement
        if (dut.flush_ex && dut.id_ex_pc != 32'h20) flushes++;
        if (dut.u_regfile.regs[4] == 7) done <= 1;
    end

    initial begin
        for (int i = 0; i < 64; i++) dut.u_imem.mem[i] = RV_NOP;
        dut.u_imem.mem[0] = rv_addi(5'd1, 5'd0, ITER);       // x1 = loop count
        dut.u_imem.mem[1] = rv_addi(5'd2, 5'd0, 12'd0);      // x2 = 0
        dut.u_imem.mem[2] = rv_addi(5'd2, 5'd2, 12'd1);      // loop: x2++
        dut.u_imem.mem[3] = rv_addi(5'd1, 5'd1, -12'sd1);    //       x1--
        dut.u_imem.mem[4] = rv_bne (5'd1, 5'd0, -13'sd8);    //       bne x1, x0, loop
        dut.u_imem.mem[5] = rv_jal (5'd0, 21'd8);            // jal -> mem[7]
        dut.u_imem.mem[6] = rv_addi(5'd3, 5'd0, 12'd99);     // skipped
        dut.u_imem.mem[7] = rv_addi(5'd4, 5'd0, 12'd7);      // x4 = 7 (end marker)
        dut.u_imem.mem[8] = rv_jal (5'd0, 21'd0);            // spin

        #12 rst_n = 1;
        wait (done || cycles > 500);
        @(posedge clk);

        $display("Loop of %0d iterations: %0d cycles, %0d pipeline flushes", ITER, cycles, flushes);
        if (dut.u_regfile.regs[2] !== ITER) begin errors++; $error("FAIL x2 loop count = %0d", dut.u_regfile.regs[2]); end
        if (dut.u_regfile.regs[3] !== 0)    begin errors++; $error("FAIL x3 (JAL shadow executed)"); end
        if (dut.u_regfile.regs[4] !== 7)    begin errors++; $error("FAIL x4 (end not reached)"); end
        // Cold BNE miss + loop exit + cold JAL miss = 3 genuine mispredictions
        if (flushes > 3) begin errors++; $error("FAIL %0d flushes: correctly predicted branches still flush", flushes); end

        if (errors == 0) $display("All checks passed - branch predictor.");
        else             $display("branch predictor FAILED: %0d errors", errors);
        $finish;
    end
endmodule
