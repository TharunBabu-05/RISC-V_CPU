// ============================================================
//  uart_tx.sv  —  UART Transmitter
//  Standard 8N1 format: 1 start bit, 8 data bits, 1 stop bit
//
//  Parameters:
//    CLK_FREQ  : System clock frequency in Hz (default 100 MHz)
//    BAUD_RATE : Baud rate (default 115200)
//
//  Interface:
//    i_data    : Byte to transmit
//    i_valid   : Pulse high for 1 cycle to start transmission
//    o_ready   : High when transmitter is idle (ready to accept)
//    o_tx      : Serial UART TX line (connect to board UART pin)
// ============================================================
`timescale 1ns/1ps

module uart_tx #(
    parameter int CLK_FREQ  = 100_000_000,  // 100 MHz Arty S7 clock
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst_n,

    // CPU-side interface
    input  logic [7:0] i_data,    // Byte to send
    input  logic       i_valid,   // Send strobe (1 cycle pulse)
    output logic       o_ready,   // '1' = idle, safe to write

    // Physical UART pin
    output logic       o_tx
);

    // -------------------------------------------------------
    //  Baud rate generator
    //  Counts from 0 to (CLKS_PER_BIT-1) to generate 1 baud tick
    // -------------------------------------------------------
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 868 @ 100 MHz / 115200

    // -------------------------------------------------------
    //  FSM states
    // -------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE  = 3'd0,
        S_START = 3'd1,
        S_DATA  = 3'd2,
        S_STOP  = 3'd3
    } state_t;

    state_t      state;
    logic [15:0] baud_cnt;   // Baud clock counter
    logic [2:0]  bit_idx;    // Current data bit index (0–7)
    logic [7:0]  shift_reg;  // Data shift register

    // -------------------------------------------------------
    //  Main FSM
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            baud_cnt  <= '0;
            bit_idx   <= '0;
            shift_reg <= '0;
            o_tx      <= 1'b1;   // UART idle line is HIGH
            o_ready   <= 1'b1;
        end else begin
            case (state)

                // ----------------------------------------
                S_IDLE: begin
                    o_tx    <= 1'b1;
                    o_ready <= 1'b1;
                    baud_cnt <= '0;

                    if (i_valid) begin
                        shift_reg <= i_data;
                        state     <= S_START;
                        o_ready   <= 1'b0;
                    end
                end

                // ----------------------------------------
                S_START: begin
                    o_tx <= 1'b0;   // START bit = LOW

                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= '0;
                        bit_idx  <= '0;
                        state    <= S_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // ----------------------------------------
                S_DATA: begin
                    o_tx <= shift_reg[bit_idx];  // LSB first

                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // ----------------------------------------
                S_STOP: begin
                    o_tx <= 1'b1;   // STOP bit = HIGH

                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= '0;
                        state    <= S_IDLE;
                        o_ready  <= 1'b1;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
