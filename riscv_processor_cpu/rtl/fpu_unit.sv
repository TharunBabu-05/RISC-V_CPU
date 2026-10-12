// ============================================================
//  fpu_unit.sv  –  IEEE-754 binary32 unit for the RV32F extension
//
//  Implements every RV32F computational instruction:
//    FADD FSUB FMUL FDIV FSQRT FMIN FMAX FSGNJ[N|X] FEQ FLT FLE FCLASS
//    FCVT.W[U].S FCVT.S.W[U] FMV.X.W FMV.W.X FMADD FMSUB FNMSUB FNMADD
//  with all five rounding modes (RNE RTZ RDN RUP RMM), subnormals,
//  canonical NaNs, and RISC-V fflags {NV, DZ, OF, UF, NX}. Underflow
//  uses tininess-after-rounding, as RISC-V requires.
//
//  FADD/FSUB/FMUL and the fused ops share one exact multiply-add
//  datapath (FADD = a*1.0 + b) followed by a single rounding step.
//  FDIV and FSQRT use radix-2 digit recurrences (27 iterations), so no
//  large combinational divider is built.
//
//  Latency: 2 cycles for most ops, 30 cycles for FDIV/FSQRT.
//  `rm` must already be resolved (0-4; the pipeline maps DYN to frm).
// ============================================================
`timescale 1ns/1ps

module fpu_unit #(
    parameter int FLEN = 32
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clear,
    input  logic        start,
    input  logic [4:0]  op,
    input  logic [2:0]  rm,
    input  logic [31:0] a,       // fs1
    input  logic [31:0] b,       // fs2
    input  logic [31:0] c,       // fs3 (fused ops)
    input  logic [31:0] x,       // integer rs1 (FCVT.S.W[U], FMV.W.X)
    output logic        busy,
    output logic        done,
    output logic [31:0] result,
    output logic [4:0]  flags    // {NV, DZ, OF, UF, NX}
);

    localparam [4:0]
        FADD = 5'd0,  FSUB = 5'd1,  FMUL = 5'd2,  FDIV = 5'd3,  FSQRT = 5'd4,
        FMIN = 5'd5,  FMAX = 5'd6,  FSGNJ = 5'd7, FSGNJN = 5'd8, FSGNJX = 5'd9,
        FEQ = 5'd10,  FLT = 5'd11,  FLE = 5'd12,  FCLASS = 5'd13,
        FCVT_W_S = 5'd14, FCVT_WU_S = 5'd15, FCVT_S_W = 5'd16, FCVT_S_WU = 5'd17,
        FMV_X_W = 5'd18,  FMV_W_X = 5'd19,
        FMADD = 5'd20, FMSUB = 5'd21, FNMSUB = 5'd22, FNMADD = 5'd23;

    localparam [2:0] RNE = 3'd0, RTZ = 3'd1, RDN = 3'd2, RUP = 3'd3, RMM = 3'd4;
    localparam [31:0] CANON_NAN = 32'h7FC0_0000;
    localparam [31:0] ONE       = 32'h3F80_0000;
    localparam [4:0]  F_NV = 5'b10000, F_DZ = 5'b01000, F_OF = 5'b00100, F_UF = 5'b00010, F_NX = 5'b00001;

    // ------------------------------------------------------------
    //  Unpacked operand: {sign, zero, inf, nan, snan, exp[9:0], sig[23:0]}
    //  For finite non-zero values sig[23] = 1 and value = sig * 2^(exp-23).
    // ------------------------------------------------------------
    localparam int U_S = 38, U_ZERO = 37, U_INF = 36, U_NAN = 35, U_SNAN = 34;

    function automatic [38:0] unpack(input [31:0] f);
        logic [7:0]  e;
        logic [22:0] m;
        logic [23:0] sig;
        logic signed [9:0] ex;
        integer lz;
        begin
            e = f[30:23];
            m = f[22:0];
            sig = 24'd0;
            ex  = 10'sd0;
            lz  = 0;
            if (e == 8'd0) begin
                if (m != 23'd0) begin
                    sig = {1'b0, m};
                    for (int i = 0; i < 24; i++)
                        if (!sig[23]) begin
                            sig = sig << 1;
                            lz  = lz + 1;
                        end
                    ex = -10'sd126 - lz;
                end
            end else begin
                sig = {1'b1, m};
                ex  = $signed({2'b00, e}) - 10'sd127;
            end
            unpack = {f[31], (e == 8'd0) && (m == 23'd0), (e == 8'hFF) && (m == 23'd0),
                      (e == 8'hFF) && (m != 23'd0), (e == 8'hFF) && (m != 23'd0) && !m[22], ex, sig};
        end
    endfunction

    function automatic logic round_inc(input [2:0] rmode, input s, input lsb, input g, input r);
        case (rmode)
            RNE:     round_inc = g & (r | lsb);
            RTZ:     round_inc = 1'b0;
            RDN:     round_inc = s & (g | r);
            RUP:     round_inc = !s & (g | r);
            RMM:     round_inc = g;
            default: round_inc = 1'b0;
        endcase
    endfunction

    // Shift M right by sh (left when sh <= 0): {kept[79:0], guard, rest}
    function automatic [81:0] extract(input [79:0] M, input st, input integer sh);
        logic [79:0] kept, mask;
        logic g, r;
        begin
            if (sh <= 0) begin
                kept = M << (-sh);
                g = 1'b0;
                r = st;
            end else if (sh > 80) begin
                kept = 80'd0;
                g = 1'b0;
                r = (|M) | st;
            end else begin
                kept = M >> sh;
                g    = M[sh-1];
                mask = (80'd1 << (sh - 1)) - 80'd1;
                r    = (|(M & mask)) | st;
            end
            extract = {kept, g, r};
        end
    endfunction

    // Round value = M * 2^E (+ sticky below M) to binary32.
    // Returns {flags[4:0], bits[31:0]}; M must be non-zero.
    function automatic [36:0] round_pack(input s, input integer E, input [79:0] M, input st, input [2:0] rmode);
        integer p, be, sh;
        logic [81:0] ex, exu;
        logic [79:0] kept, keptu;
        logic g, r, gu, ru, inc, incu, tiny, nx, of, uf;
        logic [31:0] packed_v, sum, bits;
        begin
            p = 0;
            for (int i = 0; i < 80; i++)
                if (M[i]) p = i;
            be = E + p + 127;                            // biased exponent before rounding
            sh = (be >= 1) ? (p - 23) : (p - 23 + (1 - be));
            ex   = extract(M, st, sh);
            kept = ex[81:2]; g = ex[1]; r = ex[0];
            inc  = round_inc(rmode, s, kept[0], g, r);
            nx   = g | r;
            // tininess after rounding: would 24-bit rounding reach 2^-126?
            exu   = extract(M, st, p - 23);
            keptu = exu[81:2]; gu = exu[1]; ru = exu[0];
            incu  = round_inc(rmode, s, keptu[0], gu, ru);
            tiny  = (be < 1) && !((be == 0) && (keptu[23:0] == 24'hFFFFFF) && incu);
            of = 1'b0;
            sum = 32'd0;
            if (be > 254) begin
                of = 1'b1;
            end else begin
                packed_v = (be >= 1) ? {1'b0, be[7:0], kept[22:0]} : {9'd0, kept[22:0]};
                sum = packed_v + {31'd0, inc};
                if (sum[30:23] == 8'hFF) of = 1'b1;
            end
            if (of) begin
                nx = 1'b1;
                uf = 1'b0;
                bits = (rmode == RTZ || (rmode == RDN && !s) || (rmode == RUP && s)) ?
                       {s, 31'h7F7F_FFFF} : {s, 31'h7F80_0000};
            end else begin
                uf = tiny && nx;
                bits = {s, sum[30:0]};
            end
            round_pack = {1'b0, 1'b0, of, uf, nx, bits};
        end
    endfunction

    // Place an integer whose LSB has weight 2^sh_from_base into the adder
    // window (bit 0 of the result is a sticky bit).
    function automatic [79:0] place(input [47:0] v, input integer sh);
        logic [79:0] w, mask;
        begin
            if (sh >= 0) begin
                w = {32'd0, v} << sh;
                place = {w[78:0], 1'b0};
            end else if (-sh >= 48) begin
                place = {79'd0, |v};
            end else begin
                w    = {32'd0, v} >> (-sh);
                mask = (80'd1 << (-sh)) - 80'd1;
                place = {w[78:0], |({32'd0, v} & mask)};
            end
        end
    endfunction

    // Fused (a*b) +/- c with special cases. Returns {flags, bits}.
    function automatic [36:0] fma_op(input [31:0] fa, input [31:0] fb, input [31:0] fc,
                                     input neg_prod, input neg_c, input has_c, input [2:0] rmode);
        logic [38:0] ua, ub, uc;
        logic sp, sc, rs, nan_any, snan_any;
        logic [47:0] P;
        logic [79:0] XP, XC, R;
        integer ea, eb, ec, LP, LC, msbP, top, base;
        begin
            ua = unpack(fa); ub = unpack(fb); uc = unpack(fc);
            nan_any  = ua[U_NAN]  | ub[U_NAN]  | (has_c & uc[U_NAN]);
            snan_any = ua[U_SNAN] | ub[U_SNAN] | (has_c & uc[U_SNAN]);
            sp = ua[U_S] ^ ub[U_S] ^ neg_prod;
            sc = (uc[U_S] ^ neg_c) & has_c;
            ea = $signed(ua[33:24]); eb = $signed(ub[33:24]); ec = $signed(uc[33:24]);
            if ((ua[U_INF] && ub[U_ZERO]) || (ua[U_ZERO] && ub[U_INF]))
                fma_op = {F_NV, CANON_NAN};                       // inf * 0, even with a qNaN addend
            else if (nan_any)
                fma_op = {snan_any ? F_NV : 5'd0, CANON_NAN};
            else if (ua[U_INF] || ub[U_INF]) begin
                if (has_c && uc[U_INF] && (sp != sc))
                    fma_op = {F_NV, CANON_NAN};                   // inf - inf
                else
                    fma_op = {5'd0, sp, 31'h7F80_0000};
            end else if (has_c && uc[U_INF])
                fma_op = {5'd0, sc, 31'h7F80_0000};
            else if ((ua[U_ZERO] || ub[U_ZERO]) && (!has_c || uc[U_ZERO])) begin
                // exact zero: same-sign zeros keep their sign, else +0 (-0 when RDN)
                if (!has_c)
                    fma_op = {5'd0, sp, 31'd0};
                else
                    fma_op = {5'd0, (sp == sc) ? sp : (rmode == RDN), 31'd0};
            end else if (ua[U_ZERO] || ub[U_ZERO])
                fma_op = round_pack(sc, ec - 23, {56'd0, uc[23:0]}, 1'b0, rmode);
            else begin
                P  = ua[23:0] * ub[23:0];
                LP = ea + eb - 46;
                if (!has_c || uc[U_ZERO])
                    fma_op = round_pack(sp, LP, {32'd0, P}, 1'b0, rmode);
                else begin
                    LC   = ec - 23;
                    msbP = LP + (P[47] ? 47 : 46);
                    top  = ((msbP > ec) ? msbP : ec) + 1;
                    base = top - 78;
                    XP = place(P, LP - base);
                    XC = place({24'd0, uc[23:0]}, LC - base);
                    if (sp == sc) begin
                        R = XP + XC; rs = sp;
                    end else if (XP >= XC) begin
                        R = XP - XC; rs = sp;
                    end else begin
                        R = XC - XP; rs = sc;
                    end
                    if (R == 80'd0)
                        fma_op = {5'd0, (rmode == RDN), 31'd0};
                    else
                        fma_op = round_pack(rs, base - 1, R, 1'b0, rmode);
                end
            end
        end
    endfunction

    // a < b for non-NaN operands, with -0 == +0
    function automatic logic flt_lt(input [31:0] fa, input [31:0] fb);
        if (fa[30:0] == 31'd0 && fb[30:0] == 31'd0)
            flt_lt = 1'b0;
        else if (fa[31] != fb[31])
            flt_lt = fa[31];
        else if (!fa[31])
            flt_lt = fa[30:0] < fb[30:0];
        else
            flt_lt = fa[30:0] > fb[30:0];
    endfunction

    // Float -> 32-bit integer with rounding and saturation. Returns {flags, value}.
    function automatic [36:0] fcvt_to_int(input [31:0] fa, input [2:0] rmode, input uns);
        logic [38:0] ua;
        logic [81:0] exr;
        logic [79:0] kept;
        logic [32:0] mag;
        logic s, inexact;
        integer e;
        begin
            ua = unpack(fa);
            s  = ua[U_S];
            e  = $signed(ua[33:24]);
            if (ua[U_NAN])
                fcvt_to_int = {F_NV, uns ? 32'hFFFF_FFFF : 32'h7FFF_FFFF};
            else if (ua[U_INF])
                fcvt_to_int = {F_NV, uns ? (s ? 32'h0 : 32'hFFFF_FFFF) : (s ? 32'h8000_0000 : 32'h7FFF_FFFF)};
            else if (ua[U_ZERO])
                fcvt_to_int = {5'd0, 32'd0};
            else if (e > 31)
                fcvt_to_int = {F_NV, uns ? (s ? 32'h0 : 32'hFFFF_FFFF) : (s ? 32'h8000_0000 : 32'h7FFF_FFFF)};
            else begin
                exr  = extract({56'd0, ua[23:0]}, 1'b0, 23 - e);
                kept = exr[81:2];
                mag  = kept[32:0] + {32'd0, round_inc(rmode, s, kept[0], exr[1], exr[0])};
                inexact = exr[1] | exr[0];
                if (uns) begin
                    if (s && mag != 33'd0)
                        fcvt_to_int = {F_NV, 32'h0};
                    else if (!s && mag > 33'h0_FFFF_FFFF)
                        fcvt_to_int = {F_NV, 32'hFFFF_FFFF};
                    else
                        fcvt_to_int = {inexact ? F_NX : 5'd0, mag[31:0]};
                end else begin
                    if (!s && mag > 33'h0_7FFF_FFFF)
                        fcvt_to_int = {F_NV, 32'h7FFF_FFFF};
                    else if (s && mag > 33'h0_8000_0000)
                        fcvt_to_int = {F_NV, 32'h8000_0000};
                    else
                        fcvt_to_int = {inexact ? F_NX : 5'd0, s ? (~mag[31:0] + 32'd1) : mag[31:0]};
                end
            end
        end
    endfunction

    // ------------------------------------------------------------
    //  Captured operation
    // ------------------------------------------------------------
    typedef enum logic [2:0] {S_IDLE, S_PREP, S_DIV, S_SQRT, S_FIN, S_DONE} state_t;
    state_t state;

    logic [4:0]  op_r;
    logic [2:0]  rm_r;
    logic [31:0] a_r, b_r, c_r, x_r;

    // ------------------------------------------------------------
    //  Combinational evaluation of the captured operation
    // ------------------------------------------------------------
    logic [38:0] ua_c, ub_c;
    logic [36:0] comb;               // {flags, result} for non-iterative cases
    logic        need_iter;          // finite FDIV / FSQRT
    logic        any_nan, any_snan;

    always_comb begin
        ua_c = unpack(a_r);
        ub_c = unpack(b_r);
        any_nan  = ua_c[U_NAN]  | ub_c[U_NAN];
        any_snan = ua_c[U_SNAN] | ub_c[U_SNAN];
        need_iter = 1'b0;
        comb = {5'd0, 32'd0};
        case (op_r)
            FADD:   comb = fma_op(a_r, ONE, b_r, 1'b0, 1'b0, 1'b1, rm_r);
            FSUB:   comb = fma_op(a_r, ONE, b_r, 1'b0, 1'b1, 1'b1, rm_r);
            FMUL:   comb = fma_op(a_r, b_r, 32'd0, 1'b0, 1'b0, 1'b0, rm_r);
            FMADD:  comb = fma_op(a_r, b_r, c_r, 1'b0, 1'b0, 1'b1, rm_r);
            FMSUB:  comb = fma_op(a_r, b_r, c_r, 1'b0, 1'b1, 1'b1, rm_r);
            FNMSUB: comb = fma_op(a_r, b_r, c_r, 1'b1, 1'b0, 1'b1, rm_r);
            FNMADD: comb = fma_op(a_r, b_r, c_r, 1'b1, 1'b1, 1'b1, rm_r);
            FDIV: begin
                if (any_nan)
                    comb = {any_snan ? F_NV : 5'd0, CANON_NAN};
                else if ((ua_c[U_ZERO] && ub_c[U_ZERO]) || (ua_c[U_INF] && ub_c[U_INF]))
                    comb = {F_NV, CANON_NAN};
                else if (ua_c[U_INF])
                    comb = {5'd0, ua_c[U_S] ^ ub_c[U_S], 31'h7F80_0000};
                else if (ub_c[U_INF])
                    comb = {5'd0, ua_c[U_S] ^ ub_c[U_S], 31'd0};
                else if (ub_c[U_ZERO])
                    comb = {F_DZ, ua_c[U_S] ^ ub_c[U_S], 31'h7F80_0000};
                else if (ua_c[U_ZERO])
                    comb = {5'd0, ua_c[U_S] ^ ub_c[U_S], 31'd0};
                else
                    need_iter = 1'b1;
            end
            FSQRT: begin
                if (ua_c[U_NAN])
                    comb = {ua_c[U_SNAN] ? F_NV : 5'd0, CANON_NAN};
                else if (ua_c[U_ZERO])
                    comb = {5'd0, a_r};                           // +-0
                else if (ua_c[U_S])
                    comb = {F_NV, CANON_NAN};                     // negative (incl. -inf)
                else if (ua_c[U_INF])
                    comb = {5'd0, a_r};
                else
                    need_iter = 1'b1;
            end
            FMIN, FMAX: begin
                if (ua_c[U_NAN] && ub_c[U_NAN])
                    comb[31:0] = CANON_NAN;
                else if (ua_c[U_NAN])
                    comb[31:0] = b_r;
                else if (ub_c[U_NAN])
                    comb[31:0] = a_r;
                else if ((op_r == FMIN) ? flt_lt(a_r, b_r) || (a_r[31] && !b_r[31]) :
                                          flt_lt(b_r, a_r) || (b_r[31] && !a_r[31]))
                    comb[31:0] = a_r;                             // -0 < +0 for min/max
                else
                    comb[31:0] = b_r;
                comb[36:32] = any_snan ? F_NV : 5'd0;
            end
            FSGNJ:  comb = {5'd0, b_r[31], a_r[30:0]};
            FSGNJN: comb = {5'd0, ~b_r[31], a_r[30:0]};
            FSGNJX: comb = {5'd0, a_r[31] ^ b_r[31], a_r[30:0]};
            FEQ: begin
                if (any_nan)
                    comb = {any_snan ? F_NV : 5'd0, 32'd0};
                else
                    comb = {5'd0, 31'd0, (a_r == b_r) || (ua_c[U_ZERO] && ub_c[U_ZERO])};
            end
            FLT, FLE: begin
                if (any_nan)
                    comb = {F_NV, 32'd0};
                else if (op_r == FLT)
                    comb = {5'd0, 31'd0, flt_lt(a_r, b_r)};
                else
                    comb = {5'd0, 31'd0, flt_lt(a_r, b_r) || (a_r == b_r) || (ua_c[U_ZERO] && ub_c[U_ZERO])};
            end
            FCLASS: begin
                comb[36:32] = 5'd0;
                comb[31:10] = 22'd0;
                comb[9:0] = ua_c[U_NAN]  ? (ua_c[U_SNAN] ? 10'b01_0000_0000 : 10'b10_0000_0000) :
                            ua_c[U_INF]  ? (ua_c[U_S] ? 10'b00_0000_0001 : 10'b00_1000_0000) :
                            ua_c[U_ZERO] ? (ua_c[U_S] ? 10'b00_0000_1000 : 10'b00_0001_0000) :
                            (a_r[30:23] == 8'd0) ? (ua_c[U_S] ? 10'b00_0000_0100 : 10'b00_0010_0000) :
                                                   (ua_c[U_S] ? 10'b00_0000_0010 : 10'b00_0100_0000);
            end
            FCVT_W_S:  comb = fcvt_to_int(a_r, rm_r, 1'b0);
            FCVT_WU_S: comb = fcvt_to_int(a_r, rm_r, 1'b1);
            FCVT_S_W, FCVT_S_WU: begin
                if (x_r == 32'd0)
                    comb = {5'd0, 32'd0};
                else if (op_r == FCVT_S_W && x_r[31])
                    comb = round_pack(1'b1, 0, {48'd0, ~x_r + 32'd1}, 1'b0, rm_r);
                else
                    comb = round_pack(1'b0, 0, {48'd0, x_r}, 1'b0, rm_r);
            end
            FMV_X_W: comb = {5'd0, a_r};
            FMV_W_X: comb = {5'd0, x_r};
            default: comb = {5'd0, 32'd0};
        endcase
    end

    // ------------------------------------------------------------
    //  Iterative FDIV / FSQRT
    // ------------------------------------------------------------
    logic [25:0] div_rem;      // partial remainder (< 2 * divisor)
    logic [23:0] div_den;
    logic [26:0] quo;          // quotient / root bits
    logic [53:0] sq_rad;       // remaining radicand bits
    logic [31:0] sq_rem;
    logic [4:0]  iter_cnt;
    logic        res_sign;
    integer      res_exp;

    // FSQRT operand preparation: make the exponent even
    logic [24:0] sq_sig;
    integer      sq_e;
    // (each output is assigned exactly once so the block cannot retrigger itself)
    always_comb begin
        sq_sig = ua_c[24] ? {ua_c[23:0], 1'b0} : {1'b0, ua_c[23:0]};
        sq_e   = $signed(ua_c[33:24]) - (ua_c[24] ? 1 : 0);
    end

    logic [25:0] div_diff;
    logic        div_ge;
    assign div_ge   = div_rem >= {2'b00, div_den};
    assign div_diff = div_rem - {2'b00, div_den};

    logic [31:0] sq_rem2, sq_trial;
    assign sq_rem2  = {sq_rem[29:0], sq_rad[53:52]};
    assign sq_trial = {3'b000, quo, 2'b01};


    // ------------------------------------------------------------
    //  Control
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            op_r <= 5'd0; rm_r <= 3'd0;
            a_r <= 32'd0; b_r <= 32'd0; c_r <= 32'd0; x_r <= 32'd0;
            result <= 32'd0; flags <= 5'd0;
            div_rem <= 26'd0; div_den <= 24'd0; quo <= 27'd0;
            sq_rad <= 54'd0; sq_rem <= 32'd0; iter_cnt <= 5'd0;
            res_sign <= 1'b0; res_exp <= 0;
        end else if (clear) begin
            state <= S_IDLE;
        end else begin
            case (state)
                S_IDLE: if (start) begin
                    op_r <= op; rm_r <= rm;
                    a_r <= a; b_r <= b; c_r <= c; x_r <= x;
                    state <= S_PREP;
                end
                S_PREP: begin
                    if (need_iter) begin
                        quo      <= 27'd0;
                        iter_cnt <= 5'd27;
                        if (op_r == FDIV) begin
                            div_rem  <= {2'b00, ua_c[23:0]};
                            div_den  <= ub_c[23:0];
                            res_sign <= ua_c[U_S] ^ ub_c[U_S];
                            res_exp  <= $signed(ua_c[33:24]) - $signed(ub_c[33:24]) - 26;
                            state    <= S_DIV;
                        end else begin
                            sq_rad   <= {sq_sig, 29'd0};
                            sq_rem   <= 32'd0;
                            res_sign <= 1'b0;
                            res_exp  <= (sq_e - 52) >>> 1;
                            state    <= S_SQRT;
                        end
                    end else begin
                        result <= comb[31:0];
                        flags  <= comb[36:32];
                        state  <= S_DONE;
                    end
                end
                S_DIV: begin
                    quo     <= {quo[25:0], div_ge};
                    div_rem <= (div_ge ? div_diff : div_rem) << 1;
                    iter_cnt <= iter_cnt - 5'd1;
                    if (iter_cnt == 5'd1) state <= S_FIN;
                end
                S_SQRT: begin
                    sq_rad <= sq_rad << 2;
                    if (sq_rem2 >= sq_trial) begin
                        sq_rem <= sq_rem2 - sq_trial;
                        quo    <= {quo[25:0], 1'b1};
                    end else begin
                        sq_rem <= sq_rem2;
                        quo    <= {quo[25:0], 1'b0};
                    end
                    iter_cnt <= iter_cnt - 5'd1;
                    if (iter_cnt == 5'd1) state <= S_FIN;
                end
                S_FIN: begin : final_round
                    // Rounded here (not in a separate always_comb) so that two
                    // concurrent callers of round_pack cannot retrigger each other.
                    logic [36:0] fin;
                    fin = round_pack(res_sign, res_exp, {53'd0, quo},
                                     (op_r == FDIV) ? (div_rem != 26'd0) : (sq_rem != 32'd0), rm_r);
                    result <= fin[31:0];
                    flags  <= fin[36:32];
                    state  <= S_DONE;
                end
                S_DONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = (state != S_IDLE);
    assign done = (state == S_DONE);

endmodule
