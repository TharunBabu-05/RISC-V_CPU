// ============================================================
//  tb_riscv_tests_soc.sv  –  riscv-tests on the FPGA SoC (soc_top)
//
//  Runs the real board design (cpu_top_soc + BRAM bus + UART) in
//  simulation, with the test image (linked at 0x0) loaded into BRAM.
//  Compile with -DSIMULATION; -Ptb_riscv_tests_soc.HAS_FPU=1 builds the
//  optional FPU into the core for the rv32uf tests.
//      +HEX=<image.hex> +TOHOST=<hex addr> [+TIMEOUT=<cycles>]
//  Prints: RESULT PASS | RESULT FAIL <test#> | RESULT TIMEOUT
// ============================================================
`timescale 1ns/1ps

module tb_riscv_tests_soc #(
    parameter bit HAS_FPU = 1'b0
);

    logic clk = 0, rst_btn = 1, uart_rx = 1, uart_tx;
    logic [3:0] led;
    always #5 clk = ~clk;      // MMCM is bypassed in simulation: this is the core clock

    soc_top dut (.clk_12mhz(clk), .rst_btn(rst_btn), .uart_tx(uart_tx), .uart_rx(uart_rx), .led(led));
    defparam dut.u_cpu.HAS_FPU = HAS_FPU;
    defparam dut.u_bram.INIT_FILE = "";

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

        #1;
        for (int i = 0; i < 16384; i++) dut.u_bram.mem[i] = 32'h0;
        $readmemh(hex, dut.u_bram.mem);

        #100 rst_btn = 0;
        wait (dut.rst_n);
        cycles = 0;
        word = 32'h0;
        while (word == 32'h0 && cycles < timeout) begin
            @(posedge clk);
            #2;
            word = dut.u_bram.mem[tohost[15:2]];
            cycles++;
        end

        if (word == 32'h0)
            $display("RESULT TIMEOUT after %0d cycles (pc=%h)", cycles, dut.u_cpu.pc);
        else if (word == 32'h1)
            $display("RESULT PASS in %0d cycles", cycles);
        else
            $display("RESULT FAIL test %0d (tohost=%h) after %0d cycles", word >> 1, word, cycles);
        $finish;
    end

endmodule
