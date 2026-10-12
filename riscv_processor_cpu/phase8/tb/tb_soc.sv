// ============================================================
//  tb_soc.sv  —  Top-Level Testbench for soc_top
//
//  This drives the board-level inputs so the simulation
//  shows real signal activity instead of X/Z:
//    1. 12 MHz clock (same as Arty S7 on-board oscillator)
//    2. Reset button (active-high: press → release)
//    3. UART RX idle-high (no data coming from PC)
//
//  Build (from phase8/rtl, so firmware.vmem is found):
//    iverilog -g2012 -DSIMULATION -s tb_soc -o tb_soc.vvp \
//      ../tb/tb_soc.sv *.sv ../../rtl/*.sv
//    vvp tb_soc.vvp
//
//  With SIMULATION the MMCM is bypassed: clk_sys = clk_12mhz, while
//  the UART still divides by 25 MHz / 115200 = 217, so one bit time
//  is 217 x 83.333 ns = 18,083 ns.
//
//  What to observe in the waveform:
//    - rst_n: goes high after ~20 cycles (synchronizer)
//    - led[0]: goes high when CPU is running
//    - dbg_pc: should increment by 4 each cycle (executing NOPs/firmware)
//    - uart_txd_in: if firmware prints, you'll see UART pulses
// ============================================================
`timescale 1ns/1ps

module tb_soc;

    // =========================================================
    //  Board signal declarations
    // =========================================================
    logic clk_12mhz    = 1'b0;   // Start low
    logic rst_btn      = 1'b1;   // Active-high: start with reset pressed
    logic uart_rxd_out = 1'b1;   // UART idle = high

    logic        uart_txd_in;    // FPGA TX output
    logic [3:0]  led;            // Status LEDs

    // =========================================================
    //  12 MHz clock generator  (83.333 ns period → 41.667 ns half)
    // =========================================================
    always #41.667 clk_12mhz = ~clk_12mhz;

    localparam real BIT_NS = 217 * 83.334;   // UART bit time in simulation

    // =========================================================
    //  DUT: soc_top
    // =========================================================
    soc_top dut (
        .clk_12mhz   (clk_12mhz),
        .rst_btn     (rst_btn),
        .uart_tx     (uart_txd_in),
        .uart_rx     (uart_rxd_out),
        .led         (led)
    );

    // =========================================================
    //  Reset sequence
    //  Arty S7: BTN0 is active-high (1 = pressed = reset)
    //  Hold for 10 µs, then release.
    // =========================================================
    initial begin
        $display("\n==================================================");
        $display("  RISC-V SoC — Behavioral Simulation Start");
        $display("==================================================");

        rst_btn = 1'b1;          // Reset pressed
        #10_000;                  // Hold reset for 10 µs

        rst_btn = 1'b0;          // Release reset
        $display("[%0t ns] Reset released — CPU should start booting.", $time);

        // Wait until banner finishes printing (~8.2 ms)
        #8_200_000;
        $display("\n>>> TESTBENCH: Sending 'k' (0x6B) to SoC...");
        send_uart_byte(8'h6B);

        // Wait 1 ms to observe echo
        #1_000_000;

        $display("\n[%0t ns] Sim complete. PC=%h  LED=%b",
                  $time, dut.dbg_pc, led);
        $finish;
    end

    task send_uart_byte(input [7:0] data);
        integer b;
        begin
            // Start bit
            uart_rxd_out = 1'b0;
            #(BIT_NS);
            // 8 data bits
            for (b = 0; b < 8; b = b + 1) begin
                uart_rxd_out = data[b];
                #(BIT_NS);
            end
            // Stop bit
            uart_rxd_out = 1'b1;
            #(BIT_NS);
        end
    endtask

    // UART character decoder
    initial begin
        logic [7:0] rx_byte;
        forever begin
            @(negedge uart_txd_in);
            #(BIT_NS * 1.5);         // 1.5 bit periods to mid bit 0
            for (int b = 0; b < 8; b++) begin
                rx_byte[b] = uart_txd_in;
                #(BIT_NS);
            end
            $write("%c", rx_byte);
            $fflush();
        end
    end



    // =========================================================
    //  LED monitor
    // =========================================================
    // LD2/LD3 follow the UART lines, so only LD0/LD1 are reported.
    always @(led[1:0]) begin
        $display("[%0t ns] *** LED changed: %b  (run=%b, pll_locked=%b)",
                 $time, led, led[0], led[1]);
    end

    // =========================================================
    //  Timeout watchdog (15 ms)
    // =========================================================
    initial begin
        #15_000_000;
        $display("\n[%0t ns] Simulation finished.", $time);
        $finish;
    end

endmodule
