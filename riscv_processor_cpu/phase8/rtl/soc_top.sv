// ============================================================
//  soc_top.sv  —  RV32 SoC Top-Level for Arty S7-50 (Snake build)
// ============================================================
//  This module integrates:
//    1. cpu_top_soc — RV32IM + Zicsr 5-stage pipelined processor
//    2. bram        — 64KB unified BRAM (instruction + data)
//    3. uart        — Memory-mapped UART peripheral (115200 baud)
//    4. address decoder routing CPU data accesses to BRAM / UART
//
//  ===================================================
//  Memory Map (Physical Address Space)
//  ===================================================
//    0x0000_0000 – 0x0000_FFFF  : Unified BRAM (64KB, code + data + stack)
//       Both instruction fetch (Port A) and data load/store (Port B)
//       share the same 64KB BRAM at 0x0000_0000.
//       Firmware linker script (link.ld) places everything here:
//         .text at 0x0000_0000, .data/.bss at 0x0000_C000, stack top 0x0001_0000
//    0x1000_0000 – 0x1000_000B  : UART Registers
//       +0x0: TX Write (write byte → sends over UART)
//       +0x4: RX Read  (read byte ← received from PC)
//       +0x8: Status   (bit0=TX_READY, bit1=RX_VALID)
//
//  ===================================================
//  On-chip resources used (Arty S7-50, Vivado 2020.2 post-route):
//    3,749 LUTs, 3,674 FFs, 4 DSP48E1, 16 RAMB36 tiles (64KB)
//  ===================================================
//
//  Board: Xilinx Arty S7-50 (XC7S50-CSGA324)
//  Clock: 12 MHz on-board oscillator -> clk_wiz_0 MMCM -> 25 MHz clk_sys
// ============================================================
`timescale 1ns/1ps

module soc_top (
    // ---- Board Pins ----
    input  logic        clk_12mhz,    // Arty S7 on-board 12 MHz oscillator
    input  logic        rst_btn,      // Active-high reset button (BTN0)

    // ---- UART Pins (USB-UART via onboard FTDI FT2232) ----
    // On the Arty S7 board:
    //   Pin R12 connects to FTDI RXD input  ==> FPGA UART TX (output to PC)
    //   Pin V12 connects to FTDI TXD output ==> FPGA UART RX (input from PC)
    output logic        uart_tx,      // FPGA TX → PC RX (Pin R12)
    input  logic        uart_rx,      // PC TX → FPGA RX (Pin V12)

    // ---- Status LEDs ----
    output logic [3:0]  led           // LED[0]=run, LED[1]=PLL locked
);

    // -------------------------------------------------------
    //  PLL / MMCM: Generate 25 MHz from 12 MHz board clock
    //  MMCM config (verified from clk_wiz_0 IP):
    //    CLKFBOUT_MULT_F = 62.5, DIVCLK_DIVIDE = 1, CLKOUT0_DIVIDE_F = 30
    //    => 12 MHz × 62.5 / 30 = 25 MHz
    // -------------------------------------------------------
    logic clk_sys;      // 25 MHz system clock
    logic pll_locked;

`ifndef SIMULATION
    // Xilinx MMCM (Clocking Wizard IP)
    clk_wiz_0 u_pll (
        .clk_in1 (clk_12mhz),
        .clk_out1(clk_sys),
        .locked  (pll_locked)
        // No reset port — IP was created with USE_RESET=false
    );
`else
    // Simulation bypass
    assign clk_sys = clk_12mhz;
    assign pll_locked = 1'b1;
`endif

    // -------------------------------------------------------
    //  Reset synchronizer
    //  The Arty S7 buttons are Active-High (1 when pressed).
    //  We invert it here to get an active-low reset signal.
    // -------------------------------------------------------
    logic [3:0] rst_sync_cnt;
    logic       rst_n;
    logic       rst_btn_n;

    assign rst_btn_n = !rst_btn;

    always_ff @(posedge clk_sys or negedge rst_btn_n) begin
        if (!rst_btn_n) begin
            rst_sync_cnt <= '0;
            rst_n        <= 1'b0;
        end else if (!pll_locked) begin
            rst_sync_cnt <= '0;
            rst_n        <= 1'b0;
        end else if (!rst_n) begin
            if (rst_sync_cnt == 4'hF)
                rst_n <= 1'b1;
            else
                rst_sync_cnt <= rst_sync_cnt + 1;
        end
    end

    // -------------------------------------------------------
    //  CPU signals
    // -------------------------------------------------------
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    // -------------------------------------------------------
    //  Internal bus signals
    //  cpu_top_soc exposes a separate instruction port (BRAM
    //  port A) and data port (address decoder -> BRAM / UART).
    // -------------------------------------------------------

    // -------------------------------------------------------
    //  Instruction BRAM (Port A = fetch, read-only)
    // -------------------------------------------------------
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;

    // -------------------------------------------------------
    //  Data bus (from CPU to bus fabric)
    // -------------------------------------------------------
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [31:0] dmem_rdata;
    logic        dmem_rd_en;
    logic        dmem_wr_en;
    logic [3:0]  dmem_we;      // Byte enables for store instructions
    logic [2:0]  dmem_funct3;  // From CPU MEM stage

    // -------------------------------------------------------
    //  Address Decoder (Bus Fabric)
    //  Routes data bus to correct peripheral
    // -------------------------------------------------------
    // BRAM_BASE = 0x0000_0000 must match the firmware linker script (link.ld).
    // The CPU resets to PC=0, fetches instructions from BRAM Port A (0x0000_xxxx),
    // and the stack/data also live at 0x0000_xxxx, so Port B must decode the
    // same range. Do NOT use 0x2000_0000 here — that would drop all stack accesses.
    localparam logic [31:0] BRAM_BASE  = 32'h0000_0000;
    localparam logic [31:0] BRAM_MASK  = 32'h0000_FFFF;  // 64KB window
    localparam logic [31:0] UART_BASE  = 32'h1000_0000;
    localparam logic [31:0] UART_MASK  = 32'h0000_000F;  // 16 bytes

    logic sel_bram, sel_uart;
    assign sel_bram = ((dmem_addr & ~BRAM_MASK) == BRAM_BASE);
    assign sel_uart = ((dmem_addr & ~UART_MASK) == UART_BASE);

    // -------------------------------------------------------
    //  Read data mux back to CPU
    // -------------------------------------------------------
    logic [31:0] bram_rdata;
    logic [31:0] bram_wdata;
    logic [31:0] uart_rdata;

    // Align UART read path and selects with BRAM's 1-cycle read latency:
    // Cycle N   (EX stage):  dmem_addr/sel valid. BRAM latches addr; UART outputs rdata.
    // Cycle N+1 (MEM stage): bram_rdata valid from BRAM; uart_rdata_latched valid.
    //                        Mux selects based on registered sel_*_mem.
    //                        mem_wb_mem_data latches dmem_rdata at posedge N+1.
    logic [31:0] uart_rdata_latched;
    logic        sel_bram_mem;
    logic        sel_uart_mem;

    always_ff @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            uart_rdata_latched <= 32'h0;
            sel_bram_mem       <= 1'b0;
            sel_uart_mem       <= 1'b0;
        end else begin
            uart_rdata_latched <= uart_rdata;
            sel_bram_mem       <= sel_bram;
            sel_uart_mem       <= sel_uart;
        end
    end

    always_comb begin
        dmem_rdata = 32'h0;
        if (sel_uart_mem)
            dmem_rdata = uart_rdata_latched;
        else if (sel_bram_mem)
            dmem_rdata = bram_rdata;
    end

    // -------------------------------------------------------
    //  Byte-enable generation from funct3
    // -------------------------------------------------------
    always_comb begin
        case (dmem_funct3)
            3'b000: begin // SB - store byte
                case (dmem_addr[1:0])
                    2'b00: dmem_we = 4'b0001;
                    2'b01: dmem_we = 4'b0010;
                    2'b10: dmem_we = 4'b0100;
                    2'b11: dmem_we = 4'b1000;
                    default: dmem_we = 4'b0000;
                endcase
            end
            3'b001: begin // SH - store halfword
                dmem_we = dmem_addr[1] ? 4'b1100 : 4'b0011;
            end
            default: dmem_we = dmem_wr_en ? 4'b1111 : 4'b0000; // SW
        endcase
        if (!dmem_wr_en) dmem_we = 4'b0000;
    end

    // Store data for SB/SH arrives in the low byte/halfword from the CPU.
    // Replicate it so the selected BRAM byte lanes receive the right value.
    always_comb begin
        case (dmem_funct3)
            3'b000:  bram_wdata = {4{dmem_wdata[7:0]}};    // SB
            3'b001:  bram_wdata = {2{dmem_wdata[15:0]}};   // SH
            default: bram_wdata = dmem_wdata;               // SW
        endcase
    end

    // -------------------------------------------------------
    //  Unified 64KB BRAM
    //  Port A: CPU instruction fetch
    //  Port B: CPU data load/store
    // -------------------------------------------------------
    bram #(
        .SIZE_BYTES(65536),
        // phase8/rtl/firmware.vmem. It is a source of the Vivado project
        // (create_project.tcl), so synthesis finds it by name; reset synth_1
        // after changing it. Simulations run from phase8/rtl or override it.
        .INIT_FILE ("firmware.vmem")
    ) u_bram (
        .clk    (clk_sys),
        // Port A — instruction fetch
        .a_addr (imem_addr),
        .a_rdata(imem_rdata),
        // Port B — data access
        .b_addr (dmem_addr),
        .b_wdata(bram_wdata),
        .b_we   (sel_bram ? dmem_we : 4'b0),
        .b_re   (sel_bram & dmem_rd_en),
        .b_rdata(bram_rdata)
    );

    // -------------------------------------------------------
    //  UART Peripheral
    // -------------------------------------------------------
    uart #(
        .CLK_FREQ (25_000_000),    // 25 MHz — MMCM output: 12MHz × 62.5 / 30 = 25 MHz (verified)
        .BAUD_RATE(115_200)
    ) u_uart (
        .clk        (clk_sys),
        .rst_n      (rst_n),
        .addr       (dmem_addr[3:0]),
        .wr_data    (dmem_wdata),
        .wr_en      (sel_uart & dmem_wr_en),
        .rd_en      (sel_uart & dmem_rd_en),
        .rd_data    (uart_rdata),
        .uart_tx_pin(uart_tx),
        .uart_rx_pin(uart_rx)
    );

    // -------------------------------------------------------
    //  CPU (cpu_top_soc: external instruction and data buses)
    // -------------------------------------------------------
    cpu_top_soc #(
        .XLEN(32)
    ) u_cpu (
        .clk            (clk_sys),
        .rst_n          (rst_n),
        .ext_interrupt  (1'b0),

        // Instruction bus (→ BRAM Port A)
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),

        // Data bus (→ Address decoder → BRAM/UART)
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_rdata     (dmem_rdata),
        .dmem_rd_en     (dmem_rd_en),
        .dmem_wr_en     (dmem_wr_en),
        .dmem_funct3    (dmem_funct3),

        // Debug
        .dbg_pc         (dbg_pc),
        .dbg_instr      (dbg_instr),
        .dbg_alu_result (dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    // -------------------------------------------------------
    //  Status LEDs
    // -------------------------------------------------------
    //  LD0 (green) : Solid = CPU is out of reset and running
    //  LD1 (green) : Solid = MMCM/PLL is locked (25 MHz clock stable)
    //  LD2 (green) : ON while UART TX is busy  (FPGA is sending to PC)
    //  LD3 (green) : ON while UART RX has data (byte waiting in buffer)
    //
    //  Diagnostic guide:
    //    LD0+LD1 ON, LD2 blinking on keypress = firmware running OK
    //    LD3 briefly ON when you type = UART RX received the byte
    //    LD2 always ON = CPU stuck in banner or echo TX loop
    //    LD3 always ON = UART RX stuck valid (glitch / wiring issue)
    assign led[0] = rst_n;              // CPU running (LD0)
    assign led[1] = pll_locked;         // PLL locked (LD1)
    assign led[2] = ~uart_tx;           // TX active: pulses ON when transmitting (LD2)
    assign led[3] = ~uart_rx;           // RX active: pulses ON when receiving (LD3)

endmodule
