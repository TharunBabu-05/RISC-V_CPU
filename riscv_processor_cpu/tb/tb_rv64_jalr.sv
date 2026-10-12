// ============================================================
//  tb_rv64_jalr.sv  –  RV64 JALR must keep the upper 32 target bits
// ============================================================
`timescale 1ns/1ps

module tb_rv64_jalr;
    `include "rv_encode.svh"

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top #(.XLEN(64)) dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    integer errors = 0;
    logic [63:0] pc_at_target;

    initial begin
        for (int i = 0; i < 64; i++) dut.u_imem.mem[i] = RV_NOP;
        // The instruction store only decodes addr[11:2], so 0x1_0000_0010
        // fetches mem[4]; the PC register must still hold all 64 bits.
        dut.u_imem.mem[0] = rv_addi(5'd1, 5'd0, 12'd1);
        dut.u_imem.mem[1] = rv_slli(5'd1, 5'd1, 6'd32);      // x1 = 0x1_0000_0000
        dut.u_imem.mem[2] = rv_addi(5'd1, 5'd1, 12'h10);     // x1 = 0x1_0000_0010
        dut.u_imem.mem[3] = rv_jalr(5'd2, 5'd1, 12'd0);      // jump to x1
        dut.u_imem.mem[4] = rv_addi(5'd3, 5'd0, 12'd5);      // target
        dut.u_imem.mem[5] = rv_jal (5'd0, 21'd0);

        #12 rst_n = 1;
        // The cycle after JALR resolves in EX, the PC register holds its target.
        wait (dut.id_ex_jump && dut.id_ex_opcode == 7'b1100111);
        @(posedge clk); #1;
        pc_at_target = dut.pc;
        repeat (20) @(posedge clk);

        if (pc_at_target !== 64'h1_0000_0010) begin errors++; $error("FAIL JALR target PC = %h, expected 0000000100000010", pc_at_target); end
        else $display("PASS JALR target PC = %h", pc_at_target);
        if (dut.u_regfile.regs[2] !== 64'h10) begin errors++; $error("FAIL link x2 = %h", dut.u_regfile.regs[2]); end
        if (dut.u_regfile.regs[3] !== 64'd5)  begin errors++; $error("FAIL target instruction did not run"); end

        if (errors == 0) $display("All checks passed - RV64 JALR.");
        else             $display("RV64 JALR FAILED: %0d errors", errors);
        $finish;
    end
endmodule
