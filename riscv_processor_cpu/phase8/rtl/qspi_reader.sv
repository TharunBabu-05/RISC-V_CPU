// Read-only SPI flash controller for resident firmware boot.
// Uses the universally supported 0x03 command with a 24-bit byte address.
`timescale 1ns/1ps

module qspi_reader (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [3:0]  addr,
    input  logic [31:0] wr_data,
    input  logic        wr_en,
    input  logic        rd_en,
    output logic [31:0] rd_data,

    output logic        flash_cs_n,
    output logic        flash_sck,
    output logic        flash_dq0_o,
    output logic        flash_dq0_oe,
    input  logic        flash_dq1_i
);
    localparam logic [2:0] IDLE     = 3'd0;
    localparam logic [2:0] TX_RISE  = 3'd1;
    localparam logic [2:0] TX_FALL  = 3'd2;
    localparam logic [2:0] RX_RISE  = 3'd3;
    localparam logic [2:0] RX_FALL  = 3'd4;

    logic [2:0] state;
    logic [31:0] flash_addr;
    logic [31:0] tx_shift;
    logic [7:0] rx_shift;
    logic [5:0] bit_count;
    logic [7:0] data_byte;
    logic done;

    wire busy = (state != IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            flash_addr   <= 32'b0;
            tx_shift     <= 32'b0;
            rx_shift     <= 8'b0;
            bit_count    <= 6'b0;
            data_byte    <= 8'b0;
            done         <= 1'b0;
            flash_cs_n   <= 1'b1;
            flash_sck    <= 1'b0;
            flash_dq0_o  <= 1'b0;
            flash_dq0_oe <= 1'b0;
        end else begin
            if (wr_en && addr == 4'h0)
                flash_addr <= wr_data;

            case (state)
                IDLE: begin
                    flash_cs_n   <= 1'b1;
                    flash_sck    <= 1'b0;
                    flash_dq0_oe <= 1'b0;
                    if (wr_en && addr == 4'h8 && wr_data[0]) begin
                        // Command 0x03 followed by a 24-bit byte address.
                        tx_shift     <= {8'h03, flash_addr[23:0]};
                        bit_count    <= 6'd0;
                        rx_shift     <= 8'b0;
                        done         <= 1'b0;
                        flash_cs_n   <= 1'b0;
                        flash_dq0_oe <= 1'b1;
                        flash_dq0_o  <= 1'b0; // command bit 7 of 0x03
                        state        <= TX_RISE;
                    end
                end

                TX_RISE: begin
                    flash_sck <= 1'b1;
                    state <= TX_FALL;
                end

                TX_FALL: begin
                    flash_sck <= 1'b0;
                    if (bit_count == 6'd31) begin
                        flash_dq0_oe <= 1'b0;
                        bit_count <= 6'd0;
                        state <= RX_RISE;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                        flash_dq0_o <= tx_shift[30-bit_count];
                        state <= TX_RISE;
                    end
                end

                RX_RISE: begin
                    flash_sck <= 1'b1;
                    rx_shift <= {rx_shift[6:0], flash_dq1_i};
                    state <= RX_FALL;
                end

                RX_FALL: begin
                    flash_sck <= 1'b0;
                    if (bit_count == 6'd7) begin
                        data_byte <= rx_shift;
                        flash_cs_n <= 1'b1;
                        done <= 1'b1;
                        state <= IDLE;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                        state <= RX_RISE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    always_comb begin
        rd_data = 32'b0;
        if (rd_en) begin
            case (addr)
                4'h0: rd_data = flash_addr;
                4'h4: rd_data = {24'b0, data_byte};
                4'h8: rd_data = {30'b0, done, busy};
                4'hC: rd_data = 32'h5153_5049; // "QSPI"
                default: rd_data = 32'b0;
            endcase
        end
    end
endmodule
