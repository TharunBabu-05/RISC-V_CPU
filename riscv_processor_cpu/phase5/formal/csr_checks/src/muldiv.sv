// ============================================================
//  muldiv.sv  –  RV32M/RV64M multiply/divide unit (3-cycle latency)
//  Single-issue: accepts a new op when idle, returns result after 3 cycles.
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

    localparam int WIDE = XLEN * 2;

    // Pipeline registers
    logic [XLEN-1:0] pipe0, pipe1, pipe2;
    logic [2:0]  valid;

    // Compute result combinationally for the issued op
    function automatic logic [XLEN-1:0] compute_result(
        input logic [2:0]  f3,
        input logic [XLEN-1:0] a_in,
        input logic [XLEN-1:0] b_in
    );
        logic signed [XLEN-1:0] a_s;
        logic signed [XLEN-1:0] b_s;
        logic [XLEN-1:0]        a_u;
        logic [XLEN-1:0]        b_u;
        logic signed [WIDE-1:0] prod_ss;
        logic [WIDE-1:0]        prod_su;
        logic [WIDE-1:0]        prod_uu;
        logic [XLEN-1:0]        res;
        logic [XLEN-1:0]        max_neg;
        logic [XLEN-1:0]        minus_one;
    begin
        a_s = a_in;
        b_s = b_in;
        a_u = a_in;
        b_u = b_in;
        prod_ss = a_s * b_s;
        prod_su = $signed(a_s) * $unsigned(b_u);
        prod_uu = a_u * b_u;
        max_neg = {1'b1, {(XLEN-1){1'b0}}};
        minus_one = {XLEN{1'b1}};

        case (f3)
            OP_MUL:    res = prod_ss[XLEN-1:0];
            OP_MULH:   res = prod_ss[WIDE-1:XLEN];
            OP_MULHSU: res = prod_su[WIDE-1:XLEN];
            OP_MULHU:  res = prod_uu[WIDE-1:XLEN];
            OP_DIV: begin
                if (b_in == {XLEN{1'b0}})
                    res = {XLEN{1'b1}};
                else if ((a_in == max_neg) && (b_in == minus_one))
                    res = max_neg;
                else
                    res = $signed(a_in) / $signed(b_in);
            end
            OP_DIVU: begin
                if (b_in == {XLEN{1'b0}})
                    res = {XLEN{1'b1}};
                else
                    res = a_u / b_u;
            end
            OP_REM: begin
                if (b_in == {XLEN{1'b0}})
                    res = a_in;
                else if ((a_in == max_neg) && (b_in == minus_one))
                    res = {XLEN{1'b0}};
                else
                    res = $signed(a_in) % $signed(b_in);
            end
            OP_REMU: begin
                if (b_in == {XLEN{1'b0}})
                    res = a_in;
                else
                    res = a_u % b_u;
            end
            default: res = {XLEN{1'b0}};
        endcase

        compute_result = res;
    end
    endfunction

    // Valid shift register (3-cycle latency)
    logic [2:0] valid_next;
    always_comb begin
        valid_next = {valid[1:0], 1'b0};
        if (start && !busy)
            valid_next[0] = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 3'b0;
            pipe0 <= {XLEN{1'b0}};
            pipe1 <= {XLEN{1'b0}};
            pipe2 <= {XLEN{1'b0}};
        end else if (clear) begin
            valid <= 3'b0;
            pipe0 <= {XLEN{1'b0}};
            pipe1 <= {XLEN{1'b0}};
            pipe2 <= {XLEN{1'b0}};
        end else begin
            valid <= valid_next;
            pipe2 <= pipe1;
            pipe1 <= pipe0;
            if (start && !busy)
                pipe0 <= compute_result(op, a, b);
        end
    end

    assign busy   = |valid;
    assign done   = valid[2];
    assign result = pipe2;

endmodule
