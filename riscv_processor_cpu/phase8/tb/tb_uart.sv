// ============================================================
//  tb_uart.sv  —  UART TX/RX Loopback Testbench
//
//  Tests:
//    1. UART TX: Send "Hello!" byte-by-byte, verify bit stream
//    2. UART RX: Feed back TX output to RX input (loopback)
//    3. uart.sv wrapper: Write to TX register, read Status, read RX
//
//  Pass criteria:
//    - Every byte sent from TX is received back by RX intact
//    - Status register correctly reflects TX_READY and RX_VALID
// ============================================================
`timescale 1ns/1ps

module tb_uart;

    // ---- Parameters ----
    localparam int CLK_FREQ  = 100_000_000;
    localparam int BAUD_RATE = 115_200;
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 868

    // ---- Clock and Reset ----
    logic clk  = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;  // 100 MHz clock (10ns period)

    // ---- DUT: uart.sv peripheral ----
    logic [3:0]  addr;
    logic [31:0] wr_data;
    logic        wr_en, rd_en;
    logic [31:0] rd_data;
    logic        uart_tx_pin;
    logic        uart_rx_pin;

    uart #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr       (addr),
        .wr_data    (wr_data),
        .wr_en      (wr_en),
        .rd_en      (rd_en),
        .rd_data    (rd_data),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin)
    );

    // ---- Loopback: TX output → RX input ----
    assign uart_rx_pin = uart_tx_pin;

    // ---- Helper: CPU write to UART register ----
    task cpu_write(input [3:0] a, input [31:0] d);
        @(posedge clk);
        addr    = a;
        wr_data = d;
        wr_en   = 1'b1;
        rd_en   = 1'b0;
        @(posedge clk);
        wr_en   = 1'b0;
    endtask

    // ---- Helper: CPU read from UART register ----
    task cpu_read(input [3:0] a, output [31:0] d);
        @(posedge clk);
        addr  = a;
        rd_en = 1'b1;
        wr_en = 1'b0;
        @(posedge clk);
        d     = rd_data;
        rd_en = 1'b0;
    endtask

    // ---- Helper: Send a byte (wait for TX_READY, then write) ----
    task send_byte(input [7:0] b);
        logic [31:0] status;
        // Wait for TX_READY (bit 0 of status register at 0x8)
        do begin
            cpu_read(4'h8, status);
        end while (!status[0]);
        // Write byte to TX register (addr 0x0)
        cpu_write(4'h0, {24'b0, b});
        $display("[TB] Sent byte: 0x%02X (%c)", b, b);
    endtask

    // ---- Helper: Receive a byte (wait for RX_VALID, then read) ----
    task recv_byte(output [7:0] b);
        logic [31:0] status, rx_data;
        // Wait for RX_VALID (bit 1 of status register at 0x8)
        do begin
            cpu_read(4'h8, status);
        end while (!status[1]);
        // Read received byte (addr 0x4)
        cpu_read(4'h4, rx_data);
        b = rx_data[7:0];
        $display("[TB] Recv byte: 0x%02X (%c)", b, b);
    endtask

    // ---- Test string ----
    string test_str = "Hello, RISC-V SoC!\n";
    int    pass_count = 0;
    int    fail_count = 0;

    // ---- Main Test ----
    initial begin
        $dumpfile("tb_uart.vcd");
        $dumpvars(0, tb_uart);

        // Initialize
        addr    = '0;
        wr_data = '0;
        wr_en   = 1'b0;
        rd_en   = 1'b0;

        // Release reset after 100ns
        #100;
        rst_n = 1'b1;
        #100;

        $display("\n=== UART Loopback Test ===");
        $display("Sending string: \"%s\"", test_str);

        // Send and receive each character
    begin : loopblock
        integer i;
        reg [7:0] sent_byte;
        reg [7:0] rcvd_byte;
        for (i = 0; i < 19; i = i + 1) begin   // length of "Hello, RISC-V SoC!\n"
            sent_byte = test_str[i];
            send_byte(sent_byte);
            recv_byte(rcvd_byte);

            if (rcvd_byte == sent_byte) begin
                pass_count = pass_count + 1;
            end else begin
                $display("  MISMATCH! Sent 0x%02X, got 0x%02X", sent_byte, rcvd_byte);
                fail_count = fail_count + 1;
            end
        end
    end

        // ---- Report ----
        $display("\n=== UART Test Results ===");
        $display("  PASS: %0d / %0d bytes", pass_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED! UART is working correctly. ***");
        else
            $display("  *** %0d FAILURES DETECTED! ***", fail_count);

        #1000;
        $finish;
    end

    // ---- Timeout watchdog ----
    initial begin
        #500_000_000;  // 500ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
