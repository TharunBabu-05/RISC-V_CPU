// ============================================================
//  tb_riscv_tests.sv  –  riscv-tests (isa, "p" env) on cpu_top
//
//  Driven by phase5/compliance/run_compliance.py:
//      +HEX=<image.hex>     objcopy -O verilog image rebased to 0
//      +TOHOST=<hex addr>   address of the tohost symbol (rebased)
//      +TIMEOUT=<cycles>    optional (default 200000)
//  Prints one line:  RESULT PASS | RESULT FAIL <test#> | RESULT TIMEOUT
//
//  Instruction and data memories are separate arrays in this core, so
//  every data store is mirrored into instruction memory (a unified
//  memory as seen by the self-modifying fence_i test).
// ============================================================
`timescale 1ns/1ps

module tb_riscv_tests;

    localparam int WORDS = 16384;          // 64 KiB of instruction and data memory

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    defparam dut.u_imem.WORDS = WORDS;
    defparam dut.u_dcache.u_l2.u_dram.u_dmem.WORDS = WORDS;

    `define DMEM dut.u_dcache.u_l2.u_dram.u_dmem

    // mirror data stores into instruction memory
    always @(posedge clk) begin
        if (`DMEM.mem_write) begin : mirror
            int w;
            w = `DMEM.widx;                   // address of this store (sampled at the edge)
            #1 dut.u_imem.mem[w] = `DMEM.mem[w];
        end
    end

    initial begin
        string hex;
        logic [31:0] tohost, word;
        integer timeout, cycles;

        if (!$value$plusargs("HEX=%s", hex)) begin
            $display("RESULT ERROR no +HEX");
            $finish;
        end
        if (!$value$plusargs("TOHOST=%h", tohost)) tohost = 32'h1000;
        if (!$value$plusargs("TIMEOUT=%d", timeout)) timeout = 200000;

        #1;                                   // after the memories' own initialisation
        for (int i = 0; i < WORDS; i++) `DMEM.mem[i] = 32'h0;
        $readmemh(hex, dut.u_imem.mem);
        $readmemh(hex, `DMEM.mem);

        #11 rst_n = 1;
        cycles = 0;
        word = 32'h0;
        while (word == 32'h0 && cycles < timeout) begin
            @(posedge clk);
            #2;
            word = `DMEM.mem[tohost[31:2]];
            cycles++;
        end

        if (word == 32'h0)
            $display("RESULT TIMEOUT after %0d cycles (pc=%h)", cycles, dut.pc);
        else if (word == 32'h1)
            $display("RESULT PASS in %0d cycles", cycles);
        else
            $display("RESULT FAIL test %0d (tohost=%h) after %0d cycles", word >> 1, word, cycles);
        $finish;
    end

endmodule
