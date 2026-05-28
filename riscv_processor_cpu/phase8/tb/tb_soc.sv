// ============================================================
//  tb_soc.sv  —  Top-Level Testbench for soc_top
//
//  This drives the board-level inputs so the simulation
//  shows real signal activity instead of X/Z:
//    1. 12 MHz clock (same as Arty S7 on-board oscillator)
//    2. Reset button (active-high: press → release)
//    3. UART RX idle-high (no data coming from PC)
//
//  What to observe in the waveform:
//    - clk_100mhz: should toggle at 5ns (100 MHz)
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

    // =========================================================
    //  DUT: soc_top
    // =========================================================
    soc_top dut (
        .clk_12mhz   (clk_12mhz),
        .rst_btn     (rst_btn),
        .uart_txd_in (uart_txd_in),
        .uart_rxd_out(uart_rxd_out),
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

        // Run for 2 ms to observe execution
        #2_000_000;

        $display("[%0t ns] Sim complete. PC=%h  LED=%b",
                  $time, dut.dbg_pc, led);
        $finish;
    end

    // =========================================================
    //  PC change monitor  (print every instruction fetch)
    // =========================================================
    logic [31:0] prev_pc = 32'hFFFF_FFFF;
    always @(posedge dut.clk_100mhz) begin
        if (dut.rst_n && (dut.dbg_pc !== prev_pc)) begin
            $display("[%10t ns] PC=%08h  INSTR=%08h  ALU=%08h  LED=%b",
                     $time,
                     dut.dbg_pc,
                     dut.dbg_instr,
                     dut.dbg_alu_result,
                     led);
            prev_pc <= dut.dbg_pc;
        end
    end

    // =========================================================
    //  LED monitor
    // =========================================================
    always @(led) begin
        $display("[%0t ns] *** LED changed: %b  (run=%b, pll_locked=%b)",
                 $time, led, led[0], led[1]);
    end

    // =========================================================
    //  UART TX monitor  (prints when UART start bit detected)
    // =========================================================
    always @(negedge uart_txd_in) begin
        $display("[%0t ns] *** UART TX: start bit detected (CPU sending data)", $time);
    end

    // =========================================================
    //  Timeout watchdog (5 ms)
    // =========================================================
    initial begin
        #5_000_000;
        $display("ERROR: Simulation timeout after 5ms!");
        $finish;
    end

endmodule
