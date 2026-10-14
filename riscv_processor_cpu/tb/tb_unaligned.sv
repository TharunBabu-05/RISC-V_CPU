`timescale 1ns/1ps

module tb_unaligned;
    `include "rv_encode.svh"
    logic clk=0, rst_n=0;
    always #5 clk=~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;
    cpu_top dut(.clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr), .dbg_alu_result(dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data));
    `define DMEM dut.u_dcache.u_l2.u_dram.u_dmem.mem
    integer errors=0;
    task check(input string name, input [31:0] got, input [31:0] expected);
        if(got!==expected) begin $error("FAIL %s: %h != %h",name,got,expected); errors++; end
        else $display("PASS %s = %h",name,got);
    endtask
    initial begin
        for(int i=0;i<64;i++) dut.u_imem.mem[i]=RV_NOP;
        `DMEM[64]=32'h44332211;
        `DMEM[65]=32'h88776655;
        dut.u_imem.mem[0]=rv_lw(5'd1,5'd0,12'h101);
        dut.u_imem.mem[1]=rv_lh(5'd2,5'd0,12'h103);
        dut.u_imem.mem[2]=rv_i(12'h103,5'd0,3'b101,5'd3,7'b0000011);
        dut.u_imem.mem[3]=rv_sw(5'd1,5'd0,12'h106);
        dut.u_imem.mem[4]=rv_lw(5'd4,5'd0,12'h106);
        dut.u_imem.mem[5]=rv_s(12'h10b,5'd2,5'd0,3'b001);
        dut.u_imem.mem[6]=rv_i(12'h10b,5'd0,3'b100,5'd5,7'b0000011);
        dut.u_imem.mem[7]=rv_i(12'h10c,5'd0,3'b100,5'd6,7'b0000011);
        dut.u_imem.mem[8]=rv_jal(5'd0,21'd0);
        #12 rst_n=1;
        repeat(100) @(posedge clk);
        check("unaligned LW",dut.u_regfile.regs[1],32'h55443322);
        check("cross-word signed LH",dut.u_regfile.regs[2],32'h00005544);
        check("cross-word LHU",dut.u_regfile.regs[3],32'h00005544);
        check("unaligned SW reload",dut.u_regfile.regs[4],32'h55443322);
        check("unaligned SW lower word",`DMEM[65],32'h33226655);
        check("unaligned stores upper word",`DMEM[66],32'h44005544);
        check("byte after cross-line SH",dut.u_regfile.regs[5],32'h00000044);
        check("next-line byte after SH",dut.u_regfile.regs[6],32'h00000055);
        if(errors==0) $display("All checks passed - hardware unaligned accesses.");
        else $display("unaligned access FAILED: %0d errors",errors);
        $finish;
    end
endmodule
