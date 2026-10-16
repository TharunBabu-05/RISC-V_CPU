// ============================================================
//  plic.sv - Small single-context Platform-Level Interrupt Controller
//
//  The source count is parameterized. The Phase 8 SoC uses five IDs:
//    1 UART, 2 GPIO, 3 SPI, 4 external/platform, 5 DMA
//
//  Relative register map (PLIC base 0x0C00_0000):
//    0x000004..014  source priority (0 disables, 1..7)
//    0x001000       pending source bits (read-only)
//    0x002000       machine-context enable source bits
//    0x200000       machine-context priority threshold
//    0x200004       claim (read) / complete (write)
// ============================================================
`timescale 1ns/1ps

module plic #(
    parameter int NUM_SOURCES = 4
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic [21:0]            addr,
    input  logic [31:0]            wr_data,
    input  logic                   wr_en,
    input  logic                   rd_en,
    input  logic [NUM_SOURCES-1:0] source_irq,
    output logic [31:0]            rd_data,
    output logic                   external_irq
);
    localparam logic [21:0] PENDING_ADDR   = 22'h001000;
    localparam logic [21:0] ENABLE_ADDR    = 22'h002000;
    localparam logic [21:0] THRESHOLD_ADDR = 22'h200000;
    localparam logic [21:0] CLAIM_ADDR     = 22'h200004;

    logic [2:0] irq_priority [0:NUM_SOURCES-1];
    logic [NUM_SOURCES-1:0] pending;
    logic [NUM_SOURCES-1:0] enable;
    logic [NUM_SOURCES-1:0] in_service;
    logic [2:0] threshold;
    logic [2:0] claim_id;
    logic [2:0] best_priority;
    logic       claim_read;
    integer i;

    always_comb begin
        claim_id = 3'b0;
        best_priority = 3'b0;
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin
            if (pending[i] && enable[i] &&
                irq_priority[i] > threshold && irq_priority[i] > best_priority) begin
                claim_id = i + 1;
                best_priority = irq_priority[i];
            end
        end
    end

    assign external_irq = (claim_id != 0);
    assign claim_read = rd_en && (addr == CLAIM_ADDR) && (claim_id != 0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending    <= '0;
            enable     <= '0;
            in_service <= '0;
            threshold  <= 3'b0;
            for (i = 0; i < NUM_SOURCES; i = i + 1)
                irq_priority[i] <= 3'd1;
        end else begin
            pending <= pending | (source_irq & ~in_service);

            if (claim_read) begin
                pending[claim_id - 1'b1] <= 1'b0;
                in_service[claim_id - 1'b1] <= 1'b1;
            end

            if (wr_en) begin
                for (i = 0; i < NUM_SOURCES; i = i + 1) begin
                    if (addr == ((i + 1) * 4))
                        irq_priority[i] <= wr_data[2:0];
                end

                if (addr == ENABLE_ADDR)
                    enable <= wr_data[NUM_SOURCES:1];
                else if (addr == THRESHOLD_ADDR)
                    threshold <= wr_data[2:0];
                else if (addr == CLAIM_ADDR &&
                         wr_data >= 1 && wr_data <= NUM_SOURCES)
                    in_service[wr_data - 1'b1] <= 1'b0;
            end
        end
    end

    always_comb begin
        rd_data = 32'b0;
        if (rd_en) begin
            for (i = 0; i < NUM_SOURCES; i = i + 1) begin
                if (addr == ((i + 1) * 4))
                    rd_data = {29'b0, irq_priority[i]};
            end

            if (addr == PENDING_ADDR)
                rd_data = {{(31-NUM_SOURCES){1'b0}}, pending, 1'b0};
            else if (addr == ENABLE_ADDR)
                rd_data = {{(31-NUM_SOURCES){1'b0}}, enable, 1'b0};
            else if (addr == THRESHOLD_ADDR)
                rd_data = {29'b0, threshold};
            else if (addr == CLAIM_ADDR)
                rd_data = {29'b0, claim_id};
        end
    end
endmodule
