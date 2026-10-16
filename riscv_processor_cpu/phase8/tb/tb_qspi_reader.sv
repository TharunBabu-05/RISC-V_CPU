`timescale 1ns/1ps

module tb_qspi_reader;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [3:0] addr = 4'b0;
    logic [31:0] wr_data = 32'b0;
    logic wr_en = 1'b0;
    logic rd_en = 1'b0;
    logic [31:0] rd_data;
    logic flash_cs_n;
    logic flash_sck;
    logic flash_dq0_o;
    logic flash_dq0_oe;
    logic flash_dq1_i = 1'b1;

    logic [31:0] captured_tx = 32'b0;
    integer tx_bits = 0;
    integer rx_bits = 0;
    integer errors = 0;
    localparam logic [7:0] EXPECTED_DATA = 8'hA5;

    always #5 clk = ~clk;

    qspi_reader dut (.*);

    always @(posedge flash_sck) begin
        if (!flash_cs_n && tx_bits < 32) begin
            captured_tx = {captured_tx[30:0], flash_dq0_o};
            tx_bits = tx_bits + 1;
        end
    end

    always @(negedge flash_sck) begin
        if (!flash_cs_n && tx_bits == 32 && rx_bits < 8) begin
            flash_dq1_i = EXPECTED_DATA[7-rx_bits];
            rx_bits = rx_bits + 1;
        end
    end

    task automatic write_reg(input [3:0] a, input [31:0] value);
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
        write_reg(4'h0, 32'h0012_3456);
        write_reg(4'h8, 32'h1);
        wait (dut.done);
        #1;

        check("SPI command and 24-bit address", captured_tx == 32'h0312_3456);
        check("eight response bits sampled", rx_bits == 8);
        rd_en = 1'b1;
        addr = 4'h4;
        #1;
        check("flash data register", rd_data == 32'h0000_00A5);
        addr = 4'h8;
        #1;
        check("done set and busy clear", rd_data[1:0] == 2'b10);
        rd_en = 1'b0;
        check("chip select released", flash_cs_n && !flash_sck);

        if (errors == 0)
            $display("PASS: QSPI reader command/address/data test");
        else
            $fatal(1, "QSPI reader tests failed: %0d", errors);
        $finish;
    end
endmodule
