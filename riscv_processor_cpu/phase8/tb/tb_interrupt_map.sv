`timescale 1ns/1ps

module tb_interrupt_map;
    logic clk_12mhz = 1'b0;
    logic rst_btn = 1'b1;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic [3:0] led;
    logic sim_bus_override = 1'b0;
    logic [31:0] sim_bus_addr = 32'b0;
    logic [31:0] sim_bus_wdata = 32'b0;
    logic sim_bus_rd_en = 1'b0;
    logic sim_bus_wr_en = 1'b0;
    logic [2:0] sim_bus_funct3 = 3'b010;
    logic [3:0] sim_irq_sources = 4'b0;
    logic [31:0] value;
    integer errors = 0;

    always #5 clk_12mhz = ~clk_12mhz;

    soc_top dut (.*);

    task automatic bus_write(input [31:0] a, input [31:0] data);
        begin
            @(negedge clk_12mhz);
            sim_bus_override = 1'b1;
            sim_bus_addr = a;
            sim_bus_wdata = data;
            sim_bus_funct3 = 3'b010;
            sim_bus_rd_en = 1'b0;
            sim_bus_wr_en = 1'b1;
            @(posedge clk_12mhz); #1;
            sim_bus_override = 1'b0;
            sim_bus_wr_en = 1'b0;
        end
    endtask

    task automatic bus_read(input [31:0] a, output [31:0] data);
        begin
            @(negedge clk_12mhz);
            sim_bus_override = 1'b1;
            sim_bus_addr = a;
            sim_bus_funct3 = 3'b010;
            sim_bus_rd_en = 1'b1;
            sim_bus_wr_en = 1'b0;
            @(posedge clk_12mhz); #1;
            data = dut.dmem_rdata;
            sim_bus_override = 1'b0;
            sim_bus_rd_en = 1'b0;
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
        repeat (4) @(posedge clk_12mhz);
        rst_btn = 1'b0;
        wait (dut.rst_n);
        repeat (2) @(posedge clk_12mhz);

        bus_write(32'h0200_0000, 32'h1);
        check("CLINT MSIP reaches the CPU", dut.software_irq);
        @(posedge clk_12mhz); #1;
        check("CPU mip.MSIP reflects CLINT", dut.u_cpu.u_int.mip_reg[3]);
        bus_write(32'h0200_0000, 32'h0);

        // Put mtime near zero and safely program a short timer deadline.
        bus_write(32'h0200_4004, 32'hFFFF_FFFF);
        bus_write(32'h0200_BFFC, 32'h0);
        bus_write(32'h0200_BFF8, 32'h0);
        bus_write(32'h0200_4000, 32'd20);
        bus_write(32'h0200_4004, 32'h0);
        wait (dut.timer_irq);
        check("CLINT timer reaches the CPU", dut.timer_irq);
        @(posedge clk_12mhz); #1;
        check("CPU mip.MTIP reflects CLINT", dut.u_cpu.u_int.mip_reg[7]);
        bus_write(32'h0200_4004, 32'hFFFF_FFFF);

        // Configure source 2 (GPIO slot), inject one pulse, claim and complete.
        bus_write(32'h0C00_0008, 32'd3);
        bus_write(32'h0C00_2000, 32'h0000_0004);
        @(negedge clk_12mhz);
        sim_irq_sources[1] = 1'b1;
        @(posedge clk_12mhz); #1;
        sim_irq_sources[1] = 1'b0;
        check("PLIC pending source raises MEIP", dut.plic_irq);
        @(posedge clk_12mhz); #1;
        check("CPU mip.MEIP reflects PLIC", dut.u_cpu.u_int.mip_reg[11]);

        bus_read(32'h0C20_0004, value);
        check("PLIC claim returns GPIO source ID", value == 32'd2);
        bus_write(32'h0C20_0004, 32'd2);
        check("PLIC completion leaves source inactive", !dut.plic_irq);

        if (errors == 0)
            $display("PASS: SoC CLINT/PLIC address-map integration tests");
        else
            $fatal(1, "SoC interrupt-map tests failed: %0d", errors);
        $finish;
    end
endmodule
