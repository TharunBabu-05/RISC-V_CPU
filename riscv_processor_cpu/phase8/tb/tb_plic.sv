`timescale 1ns/1ps

module tb_plic;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [21:0] addr = 22'b0;
    logic [31:0] wr_data = 32'b0;
    logic wr_en = 1'b0;
    logic rd_en = 1'b0;
    logic [3:0] source_irq = 4'b0;
    logic [31:0] rd_data;
    logic external_irq;
    integer errors = 0;

    always #5 clk = ~clk;
    plic dut (.*);

    task automatic write_reg(input [21:0] a, input [31:0] value);
        begin
            @(negedge clk);
            addr = a;
            wr_data = value;
            wr_en = 1'b1;
            @(posedge clk); #1;
            wr_en = 1'b0;
        end
    endtask

    task automatic claim(output [31:0] id);
        begin
            @(negedge clk);
            addr = 22'h200004;
            rd_en = 1'b1;
            #1 id = rd_data;
            @(posedge clk); #1;
            rd_en = 1'b0;
        end
    endtask

    task automatic pulse_sources(input [3:0] value);
        begin
            @(negedge clk);
            source_irq = value;
            @(posedge clk); #1;
            source_irq = 4'b0;
        end
    endtask

    task automatic check(input string what, input logic condition);
        if (!condition) begin
            errors = errors + 1;
            $error("FAIL %s", what);
        end else
            $display("PASS %s", what);
    endtask

    logic [31:0] id;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        write_reg(22'h000008, 32'd2); // GPIO, source 2
        write_reg(22'h000010, 32'd5); // external, source 4
        write_reg(22'h002000, 32'h1E); // enable IDs 1..4
        pulse_sources(4'b1010);        // IDs 2 and 4
        check("enabled pending source raises MEIP", external_irq);

        claim(id);
        check("highest-priority source claims first", id == 4);
        check("lower-priority pending source remains", external_irq);
        claim(id);
        check("second pending source claims next", id == 2);
        check("no claimable sources after claims", !external_irq);

        write_reg(22'h200004, 32'd4);
        write_reg(22'h200004, 32'd2);

        write_reg(22'h200000, 32'd2);
        pulse_sources(4'b0010); // source 2 priority equals threshold
        check("threshold masks equal priority", !external_irq);
        write_reg(22'h200000, 32'd1);
        check("lower threshold releases pending source", external_irq);
        claim(id);
        check("threshold-released source is claimable", id == 2);
        write_reg(22'h200004, 32'd2);

        if (errors == 0)
            $display("PASS: PLIC priority, threshold and claim/complete tests");
        else
            $fatal(1, "PLIC tests failed: %0d", errors);
        $finish;
    end
endmodule
