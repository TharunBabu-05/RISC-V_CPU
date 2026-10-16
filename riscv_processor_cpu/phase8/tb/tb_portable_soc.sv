`timescale 1ns/1ps

module tb_portable_soc;
    localparam integer TEST_CLK_HZ = 20_000_000;
    localparam integer TEST_BAUD = 115_200;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic qspi_cs;
    logic qspi_sck;
    tri [3:0] qspi_dq;
    logic [3:0] status;
    integer errors = 0;

    always #25 clk = ~clk;
    pullup(qspi_dq[1]);

    generic_fpga_top #(
        .FIRMWARE_FILE("firmware.vmem"),
        .CLK_FREQ_HZ(TEST_CLK_HZ),
        .UART_BAUD(TEST_BAUD)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx),
        .qspi_cs(qspi_cs),
        .qspi_sck(qspi_sck),
        .qspi_dq(qspi_dq),
        .status(status)
    );

    task automatic check(input string name, input logic condition);
        if (!condition) begin
            errors = errors + 1;
            $error("FAIL %s", name);
        end else begin
            $display("PASS %s", name);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        check("portable wrapper holds reset", !status[0]);
        reset_n = 1'b1;
        wait (status[0]);
        repeat (12) @(posedge clk);

        check("portable reset deasserts synchronously", dut.soc_reset_n);
        check("20 MHz UART divisor is propagated",
              dut.u_soc.u_uart.u_tx.CLKS_PER_BIT == (TEST_CLK_HZ / TEST_BAUD));
        check("CPU executes from inferred BRAM", !$isunknown(dut.u_soc.dbg_pc));
        check("UART idle level is high", uart_tx);

        if (errors == 0)
            $display("PASS: vendor-neutral SoC wrapper at 20 MHz");
        else
            $fatal(1, "Portable wrapper test failed with %0d errors", errors);
        $finish;
    end
endmodule
