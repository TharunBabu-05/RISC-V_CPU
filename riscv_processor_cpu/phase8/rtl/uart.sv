// ============================================================
//  uart.sv  —  UART Peripheral (Memory-Mapped Registers)
//
//  Memory Map (relative to UART base address):
//    Offset 0x00  [W]   : TX Data     — write byte to transmit
//    Offset 0x04  [R]   : RX Data     — read received byte
//    Offset 0x08  [R]   : Status      — bit[0]=TX_READY, bit[1]=RX_VALID,
//                                      bit[2]=RX_OVERFLOW
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
//  RX FIFO:
//    A 16-byte queue absorbs USB-UART bursts. Reading offset 0x04 removes
//    one byte. Simultaneous arrival and read preserve both operations.
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
    //  RX path — serial receiver plus 16-byte queue
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

    // A real FIFO absorbs host/FTDI bursts while firmware services the bus.
    localparam int RX_FIFO_DEPTH = 16;
    localparam int RX_PTR_W = $clog2(RX_FIFO_DEPTH);

    logic [7:0] rx_fifo [0:RX_FIFO_DEPTH-1];
    logic [RX_PTR_W-1:0] rx_write_ptr;
    logic [RX_PTR_W-1:0] rx_read_ptr;
    logic [RX_PTR_W:0]   rx_count;
    logic                rx_overflow;
    logic                rx_pop;
    logic                rx_push;
    logic                rx_valid_flag;

    assign rx_valid_flag = (rx_count != 0);
    assign rx_pop = rd_en && (addr == 4'h4) && rx_valid_flag;
    assign rx_push = rx_valid_pulse &&
                     ((rx_count < RX_FIFO_DEPTH) || rx_pop);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_write_ptr <= '0;
            rx_read_ptr  <= '0;
            rx_count     <= '0;
            rx_overflow  <= 1'b0;
        end else begin
            if (rx_push) begin
                rx_fifo[rx_write_ptr] <= rx_data_raw;
                rx_write_ptr <= rx_write_ptr + 1'b1;
            end

            if (rx_pop)
                rx_read_ptr <= rx_read_ptr + 1'b1;

            case ({rx_push, rx_pop})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase

            if (rx_valid_pulse && !rx_push)
                rx_overflow <= 1'b1;
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
                4'h4: rd_data = rx_valid_flag
                              ? {24'b0, rx_fifo[rx_read_ptr]}
                              : 32'b0;
                // Status: [2]=RX_OVERFLOW, [1]=RX_VALID, [0]=TX_READY
                4'h8: rd_data = {29'b0, rx_overflow,
                                 rx_valid_flag, tx_ready};
                default: rd_data = 32'b0;
            endcase
        end
    end

endmodule
