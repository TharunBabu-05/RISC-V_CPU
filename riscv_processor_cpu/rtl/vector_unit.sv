// ============================================================
//  vector_unit.sv  –  RVV 1.0 integer execution unit (subset)
//
//  VLEN = 128, SEW = 8/16/32 (vtype.vsew 0/1/2), LMUL = 1.
//  Executes the OPIVV / OPIVX / OPIVI / OPMVV / OPMVX instructions
//  accepted by ext_decode, decoding them from the instruction word:
//    vadd vsub vrsub vand vor vxor vsll vsrl vsra vminu vmin vmaxu
//    vmax vmul vmerge/vmv.v vmseq vmsne vmsltu vmslt vmsleu vmsle
//    vmsgtu vmsgt vredsum.vs vmv.x.s vmv.s.x
//
//  Policy: tail and inactive (masked-off) elements are left
//  undisturbed (a legal implementation of both agnostic settings).
//  Element i is active when i < vl and (vm = 1 or v0.mask[i] = 1).
//  Latency: 2 cycles.
// ============================================================
`timescale 1ns/1ps

module vector_unit #(
    parameter int VLEN = 128
) (
    input  logic            clk,
    input  logic            rst_n,
    input  logic            clear,
    input  logic            start,
    input  logic [31:0]     instr,       // vector instruction word
    input  logic [VLEN-1:0] vs1,
    input  logic [VLEN-1:0] vs2,
    input  logic [VLEN-1:0] vd_old,      // current destination (undisturbed elements)
    input  logic [VLEN-1:0] v0,          // mask register
    input  logic [31:0]     scalar,      // x[rs1]
    input  logic [2:0]      sew,         // vtype.vsew
    input  logic [31:0]     vl,
    output logic            busy,
    output logic            done,
    output logic [VLEN-1:0] result,
    output logic [31:0]     scalar_out   // vmv.x.s
);

    localparam [2:0] OPIVV = 3'b000, OPMVV = 3'b010, OPIVI = 3'b011, OPIVX = 3'b100, OPMVX = 3'b110;

    // ---------------- element helpers ----------------
    function automatic [31:0] elem(input [VLEN-1:0] v, input integer i, input [2:0] s);
        case (s)
            3'd0:    elem = {24'd0, v[i*8 +: 8]};
            3'd1:    elem = {16'd0, v[i*16 +: 16]};
            default: elem = v[i*32 +: 32];
        endcase
    endfunction

    function automatic [VLEN-1:0] set_elem(input [VLEN-1:0] v, input integer i, input [2:0] s, input [31:0] val);
        set_elem = v;
        case (s)
            3'd0:    set_elem[i*8 +: 8]   = val[7:0];
            3'd1:    set_elem[i*16 +: 16] = val[15:0];
            default: set_elem[i*32 +: 32] = val;
        endcase
    endfunction

    // sign-extend an SEW-wide value to 32 bits
    function automatic [31:0] sext(input [31:0] v, input [2:0] s);
        case (s)
            3'd0:    sext = {{24{v[7]}}, v[7:0]};
            3'd1:    sext = {{16{v[15]}}, v[15:0]};
            default: sext = v;
        endcase
    endfunction

    function automatic [31:0] trunc(input [31:0] v, input [2:0] s);
        case (s)
            3'd0:    trunc = {24'd0, v[7:0]};
            3'd1:    trunc = {16'd0, v[15:0]};
            default: trunc = v;
        endcase
    endfunction

    // ---------------- captured operands ----------------
    logic [31:0]     instr_r, scalar_r, vl_r;
    logic [VLEN-1:0] vs1_r, vs2_r, vd_r, v0_r;
    logic [2:0]      sew_r;

    // ---------------- combinational evaluation ----------------
    logic [VLEN-1:0] calc;
    logic [31:0]     calc_scalar;

    always_comb begin
        logic [5:0]  funct6;
        logic [2:0]  funct3;
        logic        vm;
        logic [31:0] imm, a, b, r, sum, sa, sb;
        logic [VLEN-1:0] res;
        logic        active, body, bit_r;
        integer      nelem, ew, shamt;

        funct6 = instr_r[31:26];
        funct3 = instr_r[14:12];
        vm     = instr_r[25];
        nelem  = 16 >> sew_r;
        ew     = 8 << sew_r;
        // shifts use the immediate as an unsigned amount, other ops sign-extend it
        imm    = (funct6 == 6'b100101 || funct6 == 6'b101000 || funct6 == 6'b101001) ?
                 {27'd0, instr_r[19:15]} : {{27{instr_r[19]}}, instr_r[19:15]};
        res    = vd_r;
        sum    = 32'd0;
        // defaults for every per-element temporary (no latches)
        a = 32'd0; b = 32'd0; r = 32'd0; sa = 32'd0; sb = 32'd0;
        active = 1'b0; body = 1'b0; bit_r = 1'b0; shamt = 0;

        if (funct3 == OPMVV && funct6 == 6'b000000) begin
            // vredsum.vs: vd[0] = vs1[0] + sum(active vs2[i])
            sum = elem(vs1_r, 0, sew_r);
            for (int i = 0; i < 16; i++)
                if (i < nelem && i < vl_r && (vm || v0_r[i]))
                    sum = sum + elem(vs2_r, i, sew_r);
            if (vl_r != 0) res = set_elem(res, 0, sew_r, trunc(sum, sew_r));
        end else if (funct3 == OPMVX && funct6 == 6'b010000) begin
            // vmv.s.x
            if (vl_r != 0) res = set_elem(res, 0, sew_r, trunc(scalar_r, sew_r));
        end else if (funct3 == OPMVV && funct6 == 6'b010000) begin
            // vmv.x.s only produces scalar_out; vd is untouched
            res = vd_r;
        end else begin
            for (int i = 0; i < 16; i++) begin
                body   = (i < nelem) && (i < vl_r);
                active = body && (vm || v0_r[i]);
                a = elem(vs2_r, i, sew_r);
                b = (funct3 == OPIVV || funct3 == OPMVV) ? elem(vs1_r, i, sew_r) :
                    (funct3 == OPIVI) ? trunc(imm, sew_r) : trunc(scalar_r, sew_r);
                sa = sext(a, sew_r);
                sb = sext(b, sew_r);
                shamt = b & (ew - 1);
                r = a;
                bit_r = 1'b0;
                case (funct6)
                    6'b000000: r = a + b;                                              // vadd
                    6'b000010: r = a - b;                                              // vsub
                    6'b000011: r = b - a;                                              // vrsub
                    6'b000100: r = (a < b) ? a : b;                                    // vminu
                    6'b000101: r = ($signed(sa) < $signed(sb)) ? a : b;                // vmin
                    6'b000110: r = (a > b) ? a : b;                                    // vmaxu
                    6'b000111: r = ($signed(sa) > $signed(sb)) ? a : b;                // vmax
                    6'b001001: r = a & b;                                              // vand
                    6'b001010: r = a | b;                                              // vor
                    6'b001011: r = a ^ b;                                              // vxor
                    6'b100101: r = (funct3 == OPMVV || funct3 == OPMVX) ? a * b        // vmul
                                                                        : a << shamt;  // vsll
                    6'b101000: r = a >> shamt;                                         // vsrl
                    6'b101001: r = $signed(sa) >>> shamt;                              // vsra
                    6'b010111: r = (vm || v0_r[i]) ? b : a;                            // vmv.v / vmerge
                    6'b011000: bit_r = (a == b);                                       // vmseq
                    6'b011001: bit_r = (a != b);                                       // vmsne
                    6'b011010: bit_r = (a < b);                                        // vmsltu
                    6'b011011: bit_r = ($signed(sa) < $signed(sb));                    // vmslt
                    6'b011100: bit_r = (a <= b);                                       // vmsleu
                    6'b011101: bit_r = ($signed(sa) <= $signed(sb));                   // vmsle
                    6'b011110: bit_r = (a > b);                                        // vmsgtu
                    6'b011111: bit_r = ($signed(sa) > $signed(sb));                    // vmsgt
                    default:   r = a;
                endcase
                if (funct6[5:3] == 3'b011) begin
                    if (active) res[i] = bit_r;                                        // mask result
                end else if (funct6 == 6'b010111) begin
                    if (body) res = set_elem(res, i, sew_r, trunc(r, sew_r));          // vmerge ignores masking
                end else if (active)
                    res = set_elem(res, i, sew_r, trunc(r, sew_r));
            end
        end

        calc        = res;
        calc_scalar = sext(elem(vs2_r, 0, sew_r), sew_r);                              // vmv.x.s
    end

    // ---------------- control ----------------
    logic [1:0] state;   // 0 idle, 1 calc, 2 done

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 2'd0;
            instr_r <= 32'd0; scalar_r <= 32'd0; vl_r <= 32'd0; sew_r <= 3'd0;
            vs1_r <= '0; vs2_r <= '0; vd_r <= '0; v0_r <= '0;
            result <= '0; scalar_out <= 32'd0;
        end else if (clear) begin
            state <= 2'd0;
        end else begin
            case (state)
                2'd0: if (start) begin
                    instr_r <= instr; scalar_r <= scalar; vl_r <= vl; sew_r <= sew;
                    vs1_r <= vs1; vs2_r <= vs2; vd_r <= vd_old; v0_r <= v0;
                    state <= 2'd1;
                end
                2'd1: begin
                    result     <= calc;
                    scalar_out <= calc_scalar;
                    state      <= 2'd2;
                end
                default: state <= 2'd0;
            endcase
        end
    end

    assign busy = (state != 2'd0);
    assign done = (state == 2'd2);

endmodule
