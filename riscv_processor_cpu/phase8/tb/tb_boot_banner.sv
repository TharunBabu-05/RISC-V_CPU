// Fast boot-path regression: prove the CPU reaches the UART peripheral.
`timescale 1ns/1ps

module tb_boot_banner;
    logic clk_12mhz = 1'b0;
    logic rst_btn = 1'b1;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic [3:0] led;
    logic qspi_cs;
    tri [3:0] qspi_dq;

    integer match_index = 0;
    logic saw_banner = 1'b0;
    string expected = "RV32";

    always #41.667 clk_12mhz = ~clk_12mhz;
    assign qspi_dq[1] = 1'b1;

    soc_top #(
        .FIRMWARE_FILE("../software/build/bootloader.vmem")
    ) dut (
        .clk_12mhz(clk_12mhz),
        .rst_btn(rst_btn),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx),
        .qspi_cs(qspi_cs),
        .qspi_dq(qspi_dq),
        .led(led)
    );

    always @(posedge dut.clk_sys) begin : monitor_uart_write
        logic [7:0] value;
        if (dut.u_soc.u_uart.tx_valid) begin
            value = dut.u_soc.u_uart.tx_data;
            $write("%c", value);
            if (value == expected[match_index]) begin
                if (match_index == expected.len() - 1) begin
                    saw_banner = 1'b1;
                    match_index = 0;
                end else begin
                    match_index = match_index + 1;
                end
            end else begin
                match_index = (value == expected[0]) ? 1 : 0;
            end
        end
    end

    initial begin
        #10_000;
        rst_btn = 1'b0;
        wait (saw_banner);
        $display("\nPASS: boot firmware reached the UART and emitted the RV32 banner.");
        $finish;
    end

    initial begin
        #5_000_000;
        $fatal(1,
               "Timeout before UART banner: pc=%08x mem_stall=%b dreq=%b dready=%b",
               dut.u_soc.u_cpu.pc,
               dut.u_soc.u_cpu.mem_stall,
               dut.u_soc.cpu_d_req_valid,
               dut.u_soc.cpu_d_req_ready);
    end
endmodule
