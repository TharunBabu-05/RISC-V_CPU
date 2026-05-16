// ============================================================
//  uart_rx.sv  —  UART Receiver
//  Standard 8N1 format: 1 start bit, 8 data bits, 1 stop bit
//
//  Parameters:
//    CLK_FREQ  : System clock frequency in Hz (default 100 MHz)
//    BAUD_RATE : Baud rate (default 115200)
//
//  Interface:
//    o_data    : Received byte (valid when o_valid pulses high)
//    o_valid   : Pulses high for 1 cycle when a byte is ready
//    i_rx      : Serial UART RX line (connect to board UART pin)
// ============================================================
`timescale 1ns/1ps

module uart_rx #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst_n,

    // Physical UART pin
    input  logic       i_rx,

    // CPU-side interface
    output logic [7:0] o_data,    // Received byte
    output logic       o_valid    // 1-cycle pulse: new byte ready
);

    localparam int CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;        // 868
    localparam int HALF_BIT      = CLKS_PER_BIT / 2;            // 434 — sample at mid-bit

    // -------------------------------------------------------
    //  Input synchronizer (2-FF to prevent metastability)
    // -------------------------------------------------------
    logic rx_d1, rx_d2, rx_sync;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
        end else begin
            rx_d1 <= i_rx;
            rx_d2 <= rx_d1;
        end
    end
    assign rx_sync = rx_d2;

    // -------------------------------------------------------
    //  FSM
    // -------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE  = 3'd0,
        S_START = 3'd1,
        S_DATA  = 3'd2,
        S_STOP  = 3'd3,
        S_DONE  = 3'd4
    } state_t;

    state_t      state;
    logic [15:0] baud_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            baud_cnt  <= '0;
            bit_idx   <= '0;
            shift_reg <= '0;
            o_data    <= '0;
            o_valid   <= 1'b0;
        end else begin
            o_valid <= 1'b0;   // Default: not valid

            case (state)

                // ----------------------------------------
                S_IDLE: begin
                    baud_cnt <= '0;
                    bit_idx  <= '0;
                    // Detect falling edge (START bit)
                    if (rx_sync == 1'b0)
                        state <= S_START;
                end

                // ----------------------------------------
                //  Wait half a baud period then confirm start bit
                // -------------------------------------------------------
                S_START: begin
                    if (baud_cnt == HALF_BIT - 1) begin
                        baud_cnt <= '0;
                        if (rx_sync == 1'b0)
                            state <= S_DATA;    // Valid start bit
                        else
                            state <= S_IDLE;    // Noise, abort
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // ----------------------------------------
                S_DATA: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt            <= '0;
                        shift_reg[bit_idx]  <= rx_sync;  // Sample at full baud
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
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= '0;
                        state    <= S_DONE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // ----------------------------------------
                S_DONE: begin
                    o_data  <= shift_reg;
                    o_valid <= 1'b1;    // 1-cycle pulse to CPU
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
