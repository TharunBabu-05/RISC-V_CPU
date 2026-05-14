// ============================================================
//  fpu_unit.sv  –  Simple FP unit (behavioral, simulation only)
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
                FPU_DIV: r_s = (b_s == 0) ? '0 : (a_s / b_s);
                default: r_s = '0;
            endcase
            fpu_calc = r_s;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 3'b000;
            res_reg    <= {FLEN{1'b0}};
        end else if (clear) begin
            valid_pipe <= 3'b000;
        end else begin
            valid_pipe <= {valid_pipe[1:0], start};
            if (start)
                res_reg <= fpu_calc(a, b, op);
        end
    end

    assign busy   = |valid_pipe;
    assign done   = valid_pipe[2];
    assign result = res_reg;

endmodule
