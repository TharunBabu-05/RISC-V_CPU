// ============================================================
//  fpu_unit.sv  –  Simple FP unit (behavioral, integer stub)
//
//  ADD/SUB/MUL complete in 3 cycles. DIV reuses the iterative
//  divider in muldiv_unit (FLEN + 2 cycles) so no single-cycle
//  combinational divider is synthesized.
// ============================================================
`timescale 1ns/1ps

module fpu_unit #(
    parameter int FLEN = 32
) (
    input  logic            clk,
    input  logic            rst_n,
    input  logic            clear,
    input  logic            start,
    input  logic [2:0]      op,
    input  logic [FLEN-1:0] a,
    input  logic [FLEN-1:0] b,
    output logic            busy,
    output logic            done,
    output logic [FLEN-1:0] result
);

    localparam [2:0]
        FPU_ADD = 3'b000,
        FPU_SUB = 3'b001,
        FPU_MUL = 3'b010,
        FPU_DIV = 3'b011;

    logic [2:0] valid_pipe;
    logic [FLEN-1:0] res_reg;

    function automatic [FLEN-1:0] fpu_calc(
        input logic [FLEN-1:0] a_bits,
        input logic [FLEN-1:0] b_bits,
        input logic [2:0]       op_i
    );
        logic signed [FLEN-1:0] a_s;
        logic signed [FLEN-1:0] b_s;
        logic signed [FLEN-1:0] r_s;
        begin
            // Integer-compatible stub for Icarus: treats inputs as signed integers.
            a_s = a_bits;
            b_s = b_bits;
            r_s = '0;
            case (op_i)
                FPU_ADD: r_s = a_s + b_s;
                FPU_SUB: r_s = a_s - b_s;
                FPU_MUL: r_s = a_s * b_s;
                default: r_s = '0;
            endcase
            fpu_calc = r_s;
        end
    endfunction

    // ---- DIV path: iterative signed divider ----
    logic            div_start, div_busy, div_done;
    logic [FLEN-1:0] div_result;
    logic            div_op_r, div_by_zero_r;

    assign div_start = start && (op == FPU_DIV);

    muldiv_unit #(.XLEN(FLEN)) u_div (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (clear),
        .start (div_start),
        .op    (3'b100),        // signed DIV
        .a     (a),
        .b     (b),
        .busy  (div_busy),
        .done  (div_done),
        .result(div_result)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe    <= 3'b000;
            res_reg       <= {FLEN{1'b0}};
            div_op_r      <= 1'b0;
            div_by_zero_r <= 1'b0;
        end else if (clear) begin
            valid_pipe <= 3'b000;
        end else begin
            valid_pipe <= {valid_pipe[1:0], start && (op != FPU_DIV)};
            if (start) begin
                div_op_r      <= (op == FPU_DIV);
                div_by_zero_r <= (b == {FLEN{1'b0}});
                if (op != FPU_DIV)
                    res_reg <= fpu_calc(a, b, op);
            end
        end
    end

    assign busy   = (|valid_pipe) || div_busy;
    assign done   = valid_pipe[2] || div_done;
    // The stub defines x/0 as 0
    assign result = div_op_r ? (div_by_zero_r ? {FLEN{1'b0}} : div_result) : res_reg;

endmodule
