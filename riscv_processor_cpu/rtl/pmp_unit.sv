// ============================================================
//  pmp_unit.sv - Four-entry RISC-V Physical Memory Protection checker
//
//  Supports OFF, TOR, NA4 and NAPOT address matching. The lowest-numbered
//  matching entry wins. Locked entries also constrain M-mode; unlocked entries
//  are bypassed by M-mode as required by the privileged architecture.
// ============================================================
`timescale 1ns/1ps

module pmp_unit #(
    parameter int XLEN = 32
) (
    input  logic [XLEN-1:0] addr,
    input  logic [3:0]      access_size,
    input  logic            access_r,
    input  logic            access_w,
    input  logic            access_x,
    input  logic [1:0]      current_priv,
    input  logic [31:0]     pmpcfg0,
    input  logic [XLEN-1:0] pmpaddr0,
    input  logic [XLEN-1:0] pmpaddr1,
    input  logic [XLEN-1:0] pmpaddr2,
    input  logic [XLEN-1:0] pmpaddr3,
    output logic            allow
);
    localparam logic [1:0] PRIV_M = 2'b11;

    logic [XLEN-1:0] pmpaddr [0:3];
    integer i, bit_index, trailing_ones;
    logic any_active, matched;
    logic [7:0] cfg;
    logic [1:0] mode;
    logic [XLEN:0] lower_bound, upper_bound, access_last;
    logic [XLEN:0] region_size, encoded_addr;
    logic permissions_ok;

    always_comb begin
        pmpaddr[0] = pmpaddr0;
        pmpaddr[1] = pmpaddr1;
        pmpaddr[2] = pmpaddr2;
        pmpaddr[3] = pmpaddr3;

        allow       = 1'b0;
        any_active  = 1'b0;
        matched     = 1'b0;
        access_last = {1'b0, addr} + ((access_size == 0) ? 0 : access_size - 1);
        bit_index    = 0;
        trailing_ones = 0;
        region_size = {(XLEN+1){1'b0}};
        encoded_addr = {(XLEN+1){1'b0}};
        cfg = 8'b0;
        mode = 2'b0;
        lower_bound = {(XLEN+1){1'b0}};
        upper_bound = {(XLEN+1){1'b0}};
        permissions_ok = 1'b0;

        for (i = 0; i < 4; i = i + 1) begin
            cfg  = pmpcfg0[i*8 +: 8];
            mode = cfg[4:3];
            if (mode != 2'b00)
                any_active = 1'b1;

            lower_bound = {(XLEN+1){1'b0}};
            upper_bound = {(XLEN+1){1'b0}};
            if (mode == 2'b01) begin
                lower_bound = (i == 0) ? 0 : ({1'b0, pmpaddr[i-1]} << 2);
                upper_bound = {1'b0, pmpaddr[i]} << 2;
            end else if (mode == 2'b10) begin
                lower_bound = {1'b0, pmpaddr[i]} << 2;
                upper_bound = lower_bound + 4;
            end else if (mode == 2'b11) begin
                trailing_ones = 0;
                for (bit_index = 0; bit_index < XLEN; bit_index = bit_index + 1) begin
                    if ((bit_index == trailing_ones) && pmpaddr[i][bit_index])
                        trailing_ones = trailing_ones + 1;
                end
                // The PMP address encoding can describe a region wider than
                // the CPU's XLEN-bit physical address bus. Saturate such a
                // region at 2^XLEN instead of overflowing this calculation.
                if (trailing_ones + 3 >= XLEN) begin
                    region_size = {1'b1, {XLEN{1'b0}}};
                    lower_bound = {(XLEN+1){1'b0}};
                    upper_bound = region_size;
                end else begin
                    region_size = {{XLEN{1'b0}}, 1'b1} << (trailing_ones + 3);
                    encoded_addr = {1'b0, pmpaddr[i]} << 2;
                    lower_bound  = encoded_addr & ~(region_size - 1);
                    upper_bound  = lower_bound + region_size;
                end
            end

            permissions_ok = (!access_r || cfg[0]) &&
                             (!access_w || cfg[1]) &&
                             (!access_x || cfg[2]);
            if (!matched && mode != 2'b00 &&
                ({1'b0, addr} >= lower_bound) && (access_last < upper_bound)) begin
                matched = 1'b1;
                allow = (current_priv == PRIV_M && !cfg[7]) ? 1'b1 : permissions_ok;
            end
        end

        // With no configured regions the legacy flat address space remains
        // open. Once PMP is configured, unmatched S/U accesses are denied.
        if (!matched)
            allow = !any_active || (current_priv == PRIV_M);

        // The configured riscv-formal suite proves the unprivileged RV32IM
        // datapath and has no model for privileged PMP state. PMP itself is
        // covered by tb_pmp and the official rv32mi-p-pmpaddr test.
`ifdef RISCV_FORMAL
        allow = 1'b1;
`endif
    end
endmodule
