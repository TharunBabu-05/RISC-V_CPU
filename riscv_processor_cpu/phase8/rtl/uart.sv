// ============================================================
//  uart.sv  —  UART Peripheral (Memory-Mapped Registers)
//
//  Memory Map (relative to UART base address):
//    Offset 0x00  [W]   : TX Data     — write byte to transmit
//    Offset 0x04  [R]   : RX Data     — read received byte
//    Offset 0x08  [R]   : Status      — bit[0]=TX_READY, bit[1]=RX_VALID
//
//  The CPU reads Status before reading RX or writing TX to avoid
//  data loss. This is the standard "polled UART" pattern used
//  in embedded systems.
//
//  Example C usage (from game firmware):
//    void uart_putc(char c) {
//        while(!(UART_STATUS & 0x1));  // Wait TX ready
//        UART_TX = c;
//    }
//    char uart_getc() {
//        while(!(UART_STATUS & 0x2));  // Wait RX valid
//        return UART_RX;
//    }
//
//  RX holding register:
//    rx_valid_flag is SET  when uart_rx signals o_valid.
//    rx_valid_flag is CLEAR when the CPU reads offset 0x04 (RX Data).
//    Priority: the CPU read-clear takes precedence over the set,
//    so a new arriving byte while the CPU is reading does NOT cause
//    the flag to be immediately re-raised for the new byte — instead
//    the new byte is stored in rx_hold for the next poll cycle.
// ============================================================
`timescale 1ns/1ps

module uart #(
    parameter int CLK_FREQ  = 25_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic        clk,
    input  logic        rst_n,

    // ---- CPU memory-mapped bus interface ----
    input  logic [3:0]  addr,        // Word-aligned offset within UART region
    input  logic [31:0] wr_data,     // Write data from CPU
    input  logic        wr_en,       // Write enable
    input  logic        rd_en,       // Read enable
    output logic [31:0] rd_data,     // Read data to CPU

    // ---- Physical UART pins (connect to board) ----
    output logic        uart_tx_pin, // To FPGA TX pin (goes to PC)
    input  logic        uart_rx_pin  // From FPGA RX pin (from PC)
);

    // -------------------------------------------------------
    //  TX path
    // -------------------------------------------------------
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_ready;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_data (tx_data),
        .i_valid(tx_valid),
        .o_ready(tx_ready),
        .o_tx   (uart_tx_pin)
    );

    // -------------------------------------------------------
    //  RX path — with 1-byte FIFO (holding register)
    // -------------------------------------------------------
    logic [7:0] rx_data_raw;
    logic       rx_valid_pulse;

    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_rx   (uart_rx_pin),
        .o_data (rx_data_raw),
        .o_valid(rx_valid_pulse)
    );

    // RX holding register + valid flag
    //
    // Priority rules (to avoid the same-cycle race condition):
    //   1. CPU READ-CLEAR takes highest priority — if CPU reads RX in the
    //      same cycle that a new byte arrives, the flag is cleared and the
    //      new byte is stored in rx_hold.  The flag stays 0 until the CPU
    //      polls STATUS again and sees the next arrival.
    //   2. ARRIVE-ONLY — if a new byte arrives without a concurrent CPU read,
    //      rx_hold and rx_valid_flag are updated normally.
    //   3. CLEAR-ONLY — if the CPU reads RX with no concurrent arrival,
    //      rx_valid_flag is cleared.
    logic [7:0] rx_hold;
    logic       rx_valid_flag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_hold       <= '0;
            rx_valid_flag <= 1'b0;
        end else begin
            // Case: CPU is reading RX register right now
            if (rd_en && addr == 4'h4) begin
                rx_valid_flag <= 1'b0;   // Clear flag (CPU read clears it)
                // If a new byte also arrived this cycle, store it but keep
                // flag=0; next STATUS poll will NOT show it yet — the new byte
                // will appear on the NEXT rx_valid_pulse. This avoids a
                // false re-enter of the echo loop.
                if (rx_valid_pulse)
                    rx_hold <= rx_data_raw;  // Store new byte, but flag stays 0
            end else if (rx_valid_pulse) begin
                // Normal arrival — no concurrent CPU read
                rx_hold       <= rx_data_raw;
                rx_valid_flag <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------
    //  TX write register (addr 0x00)
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data  <= '0;
            tx_valid <= 1'b0;
        end else begin
            tx_valid <= 1'b0;   // Default: not sending

            if (wr_en && addr == 4'h0 && tx_ready) begin
                tx_data  <= wr_data[7:0];
                tx_valid <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------
    //  CPU Read Mux
    // -------------------------------------------------------
    always_comb begin
        rd_data = 32'b0;
        if (rd_en) begin
            case (addr)
                4'h4: rd_data = {24'b0, rx_hold};               // RX Data
                4'h8: rd_data = {30'b0, rx_valid_flag, tx_ready}; // Status: [1]=RX_VALID, [0]=TX_READY
                default: rd_data = 32'b0;
            endcase
        end
    end

endmodule
