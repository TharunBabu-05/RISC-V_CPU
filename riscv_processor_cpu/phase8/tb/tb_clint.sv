`timescale 1ns/1ps

module tb_clint;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [15:0] addr = 16'b0;
    logic [31:0] wr_data = 32'b0;
    logic wr_en = 1'b0;
    logic rd_en = 1'b0;
    logic [31:0] rd_data;
    logic software_irq;
    logic timer_irq;
    integer errors = 0;

    always #5 clk = ~clk;

    clint dut (.*);

    task automatic write_reg(input [15:0] a, input [31:0] value);
        begin
            @(negedge clk);
            addr = a;
            wr_data = value;
            wr_en = 1'b1;
            @(posedge clk); #1;
            wr_en = 1'b0;
        end
    endtask

    task automatic check(input string what, input logic condition);
        if (!condition) begin
            errors = errors + 1;
            $error("FAIL %s", what);
        end else
            $display("PASS %s", what);
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;

        check("timer starts inactive", !timer_irq);
        check("software interrupt starts inactive", !software_irq);

        write_reg(16'h0000, 32'h1);
        check("msip asserts machine software interrupt", software_irq);
        write_reg(16'h0000, 32'h0);
        check("msip clears machine software interrupt", !software_irq);

        // Program mtimecmp safely on RV32: high=max, low, final high.
        write_reg(16'h4004, 32'hFFFF_FFFF);
        write_reg(16'h4000, 32'd20);
        write_reg(16'h4004, 32'd0);
        wait (timer_irq);
        check("mtime >= mtimecmp asserts timer interrupt", timer_irq);

        write_reg(16'h4004, 32'hFFFF_FFFF);
        check("moving mtimecmp into future clears timer interrupt", !timer_irq);

        rd_en = 1'b1;
        addr = 16'hBFF8;
        #1;
        check("mtime register is readable", rd_data != 32'b0);
        rd_en = 1'b0;

        if (errors == 0)
            $display("PASS: CLINT register and interrupt tests");
        else
            $fatal(1, "CLINT tests failed: %0d", errors);
        $finish;
    end
endmodule
