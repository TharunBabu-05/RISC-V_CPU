// ============================================================
//  vector_unit.sv - Minimal integer vector execution unit
//  Four 32-bit lanes when VLEN=128.
// ============================================================
`timescale 1ns/1ps

module vector_unit #(
    parameter int VLEN = 128
) (
    input  logic            clk,
    input  logic            rst_n,
    input  logic            clear,
    input  logic            start,
    input  logic [2:0]      op,
    input  logic [VLEN-1:0] a,
    input  logic [VLEN-1:0] b,
    input  logic [31:0]     vl,
    output logic            busy,
    output logic            done,
    output logic [VLEN-1:0] result
);

    localparam [2:0]
        VEC_ADD = 3'b000,
        VEC_SUB = 3'b001,
        VEC_AND = 3'b010,
        VEC_OR  = 3'b011,
        VEC_XOR = 3'b100;

    localparam int LANES = VLEN / 32;

    logic [1:0] valid_pipe;
    logic [VLEN-1:0] res_reg;

    function automatic [VLEN-1:0] calc(
        input logic [VLEN-1:0] a_i,
        input logic [VLEN-1:0] b_i,
        input logic [2:0] op_i,
        input logic [31:0] vl_i
    );
        logic [VLEN-1:0] out;
        logic [31:0] av, bv, rv;
        begin
            out = a_i;
            for (int i = 0; i < LANES; i = i + 1) begin
                av = a_i[(i*32) +: 32];
                bv = b_i[(i*32) +: 32];
                rv = av;
                if (i < vl_i) begin
                    case (op_i)
                        VEC_ADD: rv = av + bv;
                        VEC_SUB: rv = av - bv;
                        VEC_AND: rv = av & bv;
                        VEC_OR : rv = av | bv;
                        VEC_XOR: rv = av ^ bv;
                        default: rv = av;
                    endcase
                end
                out[(i*32) +: 32] = rv;
            end
            calc = out;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 2'b00;
            res_reg <= {VLEN{1'b0}};
        end else if (clear) begin
            valid_pipe <= 2'b00;
        end else begin
            valid_pipe <= {valid_pipe[0], start};
            if (start)
                res_reg <= calc(a, b, op, vl);
        end
    end

    assign busy = |valid_pipe;
    assign done = valid_pipe[1];
    assign result = res_reg;

endmodule
