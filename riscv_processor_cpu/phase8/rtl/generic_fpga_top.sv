// Vendor-neutral board wrapper for the Phase 8 RV32 SoC.
//
// Feed this module a stable clock at CLK_FREQ_HZ. If a board needs a PLL,
// instantiate that vendor's PLL in a small board wrapper and connect its
// output here. QSPI SCK is an ordinary output; boards that expose their
// configuration flash only through a startup primitive need a custom wrapper
// like the Arty S7 soc_top module.
`timescale 1ns/1ps

module generic_fpga_top #(
    parameter FIRMWARE_FILE = "firmware.vmem",
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer UART_BAUD = 115_200,
    parameter integer BRAM_SIZE_BYTES = 65_536
) (
    input  logic        clk,
    input  logic        reset_n,
    output logic        uart_tx,
    input  logic        uart_rx,
    output logic        qspi_cs,
    output logic        qspi_sck,
    inout  wire [3:0]   qspi_dq,
    output logic [3:0]  status
);
    logic [3:0] reset_pipe;
    logic       soc_reset_n;
    logic       qspi_dq0_o;
    logic       qspi_dq0_oe;

    // Asynchronous assertion and synchronous deassertion make reset portable
    // across FPGA families while keeping release aligned to the system clock.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            reset_pipe <= 4'b0000;
        else
            reset_pipe <= {reset_pipe[2:0], 1'b1};
    end
    assign soc_reset_n = reset_pipe[3];

    assign qspi_dq[0] = qspi_dq0_oe ? qspi_dq0_o : 1'bz;
    assign qspi_dq[1] = 1'bz;
    assign qspi_dq[2] = 1'bz;
    assign qspi_dq[3] = 1'bz;

    soc_core #(
        .FIRMWARE_FILE  (FIRMWARE_FILE),
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .UART_BAUD      (UART_BAUD),
        .BRAM_SIZE_BYTES(BRAM_SIZE_BYTES)
    ) u_soc (
        .clk_sys     (clk),
        .rst_n       (soc_reset_n),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        .qspi_cs     (qspi_cs),
        .qspi_sck    (qspi_sck),
        .qspi_dq0_o  (qspi_dq0_o),
        .qspi_dq0_oe (qspi_dq0_oe),
        .qspi_dq1_i  (qspi_dq[1]),
        .status      (status)
    );
endmodule
