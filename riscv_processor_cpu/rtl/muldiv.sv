// ============================================================
//  muldiv.sv  –  RV32M/RV64M multiply/divide unit (multi-cycle)
//
//  Single-issue: accepts a new op when idle (start && !busy) and
//  pulses `done` for one cycle when `result` is valid. `busy` stays
//  high through the done cycle so the same op is never re-issued.
//
//  Latency:
//    MUL/MULH/MULHSU/MULHU : 3 cycles  (capture -> multiply -> select)
//    DIV/DIVU/REM/REMU     : XLEN + 2  (capture -> XLEN iterations -> sign fix)
//
//  Operands are registered on start, so the EX forwarding network is
//  not part of any arithmetic timing path. Division is a radix-2
//  restoring divider (one quotient bit per cycle) instead of a
//  single-cycle combinational divider, which needed ~100 ns of logic.
// ============================================================
`timescale 1ns/1ps

module muldiv_unit #(
    parameter int XLEN = 32
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clear,   // pipeline flush
    input  logic        start,
    input  logic [2:0]  op,
    input  logic [XLEN-1:0] a,
    input  logic [XLEN-1:0] b,
    output logic        busy,
    output logic        done,
    output logic [XLEN-1:0] result
);

    // Operation encoding (funct3)
    localparam [2:0]
        OP_MUL    = 3'b000,
        OP_MULH   = 3'b001,
        OP_MULHSU = 3'b010,
        OP_MULHU  = 3'b011,
        OP_DIV    = 3'b100,
        OP_DIVU   = 3'b101,
        OP_REM    = 3'b110,
        OP_REMU   = 3'b111;

    localparam int CNT_BITS = $clog2(XLEN) + 1;

    typedef enum logic [2:0] {
        S_IDLE, S_MUL, S_MUL_SEL, S_DIV, S_DIV_FIX, S_DONE
    } state_t;

    state_t state;

    // Captured operation
    logic [2:0]      op_r;
    logic [XLEN-1:0] a_r, b_r;

    // ---------------- Multiplier ----------------
    // One (XLEN+1)x(XLEN+1) signed multiply covers all four variants:
    // each operand is sign- or zero-extended by one bit depending on op.
    logic            a_signed_mul, b_signed_mul;
    logic signed [XLEN:0]       mul_a, mul_b;
    logic signed [2*XLEN+1:0]   mul_full;
    logic [2*XLEN-1:0]          prod_r;

    assign a_signed_mul = (op_r == OP_MULH) || (op_r == OP_MULHSU);
    assign b_signed_mul = (op_r == OP_MULH);
    assign mul_a    = $signed({a_signed_mul & a_r[XLEN-1], a_r});
    assign mul_b    = $signed({b_signed_mul & b_r[XLEN-1], b_r});
    assign mul_full = mul_a * mul_b;

    // ---------------- Divider ----------------
    logic [XLEN-1:0]     quo, rem, dvsr;
    logic                quo_neg, rem_neg;
    logic [CNT_BITS-1:0] cnt;

    // Restoring step: shift the next dividend bit into the partial
    // remainder and subtract the divisor if it fits.
    logic [XLEN:0]   rem_shift;
    logic [XLEN+1:0] trial;
    assign rem_shift = {rem, quo[XLEN-1]};
    assign trial     = {1'b0, rem_shift} - {2'b00, dvsr};

    // Operand preparation at start (absolute values for signed ops)
    logic            div_signed;
    logic            a_neg, b_neg;
    logic [XLEN-1:0] a_abs, b_abs;

    assign div_signed = (op == OP_DIV) || (op == OP_REM);
    assign a_neg = div_signed && a[XLEN-1];
    assign b_neg = div_signed && b[XLEN-1];
    assign a_abs = a_neg ? (~a + 1'b1) : a;
    assign b_abs = b_neg ? (~b + 1'b1) : b;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            op_r    <= 3'b0;
            a_r     <= {XLEN{1'b0}};
            b_r     <= {XLEN{1'b0}};
            prod_r  <= {2*XLEN{1'b0}};
            quo     <= {XLEN{1'b0}};
            rem     <= {XLEN{1'b0}};
            dvsr    <= {XLEN{1'b0}};
            quo_neg <= 1'b0;
            rem_neg <= 1'b0;
            cnt     <= '0;
            result  <= {XLEN{1'b0}};
        end else if (clear) begin
            state <= S_IDLE;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        op_r <= op;
                        a_r  <= a;
                        b_r  <= b;
                        if (op[2]) begin
                            // Division: dividend bits are shifted out of quo
                            quo     <= a_abs;
                            rem     <= {XLEN{1'b0}};
                            dvsr    <= b_abs;
                            // Divide by zero returns all-ones quotient and the
                            // dividend as remainder; never negate that quotient.
                            quo_neg <= (a_neg ^ b_neg) && (b != {XLEN{1'b0}});
                            rem_neg <= a_neg;
                            cnt     <= XLEN[CNT_BITS-1:0];
                            state   <= S_DIV;
                        end else begin
                            state <= S_MUL;
                        end
                    end
                end

                S_MUL: begin
                    prod_r <= mul_full[2*XLEN-1:0];
                    state  <= S_MUL_SEL;
                end

                S_MUL_SEL: begin
                    result <= (op_r == OP_MUL) ? prod_r[XLEN-1:0] : prod_r[2*XLEN-1:XLEN];
                    state  <= S_DONE;
                end

                S_DIV: begin
                    if (!trial[XLEN+1]) begin
                        rem <= trial[XLEN-1:0];
                        quo <= {quo[XLEN-2:0], 1'b1};
                    end else begin
                        rem <= rem_shift[XLEN-1:0];
                        quo <= {quo[XLEN-2:0], 1'b0};
                    end
                    cnt <= cnt - 1'b1;
                    if (cnt == 1)
                        state <= S_DIV_FIX;
                end

                S_DIV_FIX: begin
                    if (op_r == OP_DIV || op_r == OP_DIVU)
                        result <= quo_neg ? (~quo + 1'b1) : quo;
                    else
                        result <= rem_neg ? (~rem + 1'b1) : rem;
                    state <= S_DONE;
                end

                S_DONE: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = (state != S_IDLE);
    assign done = (state == S_DONE);

endmodule
