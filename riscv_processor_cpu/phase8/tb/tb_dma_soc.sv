`timescale 1ns/1ps

module tb_dma_soc;
    logic clk_12mhz = 1'b0;
    logic rst_btn = 1'b1;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic qspi_cs;
    tri [3:0] qspi_dq;
    logic [3:0] led;
    logic sim_bus_override = 1'b1;
    logic [31:0] sim_bus_addr = 32'b0;
    logic [31:0] sim_bus_wdata = 32'b0;
    logic sim_bus_rd_en = 1'b0;
    logic sim_bus_wr_en = 1'b0;
    logic [2:0] sim_bus_funct3 = 3'b010;
    logic [3:0] sim_irq_sources = 4'b0;
    logic [31:0] value;
    logic [7:0] tx_bytes [0:1];
    integer tx_count = 0;
    integer errors = 0;
    integer timeout;

    always #5 clk_12mhz = ~clk_12mhz;

    soc_top dut (.*);

    always @(posedge clk_12mhz) begin
        if (dut.u_soc.u_uart.tx_valid && tx_count < 2) begin
            tx_bytes[tx_count] = dut.u_soc.u_uart.tx_data;
            tx_count = tx_count + 1;
        end
    end

    task automatic bus_write_width(input [31:0] address,
                                   input [31:0] data,
                                   input [2:0] width);
        begin
            @(negedge clk_12mhz);
            sim_bus_addr = address;
            sim_bus_wdata = data;
            sim_bus_funct3 = width;
            sim_bus_rd_en = 1'b0;
            sim_bus_wr_en = 1'b1;
            while (!dut.u_soc.host_req_ready) @(posedge clk_12mhz);
            @(posedge clk_12mhz); #1;
            sim_bus_wr_en = 1'b0;
            while (!dut.u_soc.sim_rsp_valid) @(posedge clk_12mhz);
        end
    endtask

    task automatic bus_write(input [31:0] address, input [31:0] data);
        bus_write_width(address, data, 3'b010);
    endtask

    task automatic bus_read(input [31:0] address, output [31:0] data);
        begin
            @(negedge clk_12mhz);
            sim_bus_addr = address;
            sim_bus_funct3 = 3'b010;
            sim_bus_rd_en = 1'b1;
            sim_bus_wr_en = 1'b0;
            while (!dut.u_soc.host_req_ready) @(posedge clk_12mhz);
            @(posedge clk_12mhz); #1;
            sim_bus_rd_en = 1'b0;
            while (!dut.u_soc.sim_rsp_valid) @(posedge clk_12mhz);
            data = dut.u_soc.sim_rsp_rdata;
        end
    endtask

    task automatic wait_dma_idle;
        begin
            timeout = 0;
            while (dut.u_soc.u_dma.busy && timeout < 20000) begin
                @(posedge clk_12mhz);
                timeout = timeout + 1;
            end
            if (timeout == 20000) begin
                errors = errors + 1;
                $error("DMA integration timeout");
            end
        end
    endtask

    task automatic check(input string what, input logic condition);
        begin
            if (!condition) begin
                errors = errors + 1;
                $error("FAIL %s", what);
            end else begin
                $display("PASS %s", what);
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk_12mhz);
        rst_btn = 1'b0;
        wait (dut.rst_n);
        repeat (2) @(posedge clk_12mhz);

        bus_read(32'h1000_2018, value);
        check("DMA mapped peripheral ID", value == 32'h444D_4131);

        bus_write(32'h0000_0200, 32'h4433_2211);
        bus_write(32'h0000_0204, 32'h8877_6655);

        // Enable PLIC source 5 and start an interrupting 8-byte RAM copy.
        bus_write(32'h0C00_0014, 32'd4);
        bus_write(32'h0C00_2000, 32'h0000_0020);
        bus_write(32'h1000_2000, 32'h0000_0200);
        bus_write(32'h1000_2004, 32'h0000_0300);
        bus_write(32'h1000_2008, 32'd8);
        bus_write(32'h1000_200C, 32'h0000_0037);
        wait_dma_idle();

        bus_read(32'h0000_0300, value);
        check("DMA copied first BRAM word", value == 32'h4433_2211);
        bus_read(32'h0000_0304, value);
        check("DMA copied second BRAM word", value == 32'h8877_6655);
        check("DMA completion reaches PLIC", dut.u_soc.plic_irq);
        bus_read(32'h0C20_0004, value);
        check("PLIC claims DMA source ID 5", value == 32'd5);

        // Clear the level source before completing its PLIC claim.
        bus_write(32'h1000_2010, 32'h0000_000A);
        bus_write(32'h0C20_0004, 32'd5);
        repeat (2) @(posedge clk_12mhz);
        check("DMA interrupt clears cleanly", !dut.u_soc.dma_irq && !dut.u_soc.plic_irq);

        // Fixed UART destination: the DMA must wait for TX ready between bytes.
        bus_write_width(32'h0000_0220, 32'h0000_004F, 3'b000); // O
        bus_write_width(32'h0000_0221, 32'h0000_004B, 3'b000); // K
        bus_write(32'h1000_2000, 32'h0000_0220);
        bus_write(32'h1000_2004, 32'h1000_0000);
        bus_write(32'h1000_2008, 32'd2);
        bus_write(32'h1000_200C, 32'h0000_0003);
        wait_dma_idle();
        repeat (4) @(posedge clk_12mhz);
        check("UART DMA emitted two writes", tx_count == 2);
        check("UART DMA preserved byte order",
              tx_bytes[0] == 8'h4F && tx_bytes[1] == 8'h4B);

        if (errors == 0)
            $display("PASS: SoC DMA/BRAM/UART/PLIC integration tests");
        else
            $fatal(1, "SoC DMA integration tests failed: %0d", errors);
        $finish;
    end
endmodule
