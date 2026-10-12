"""
fpu_ref.py - Bit-exact reference model of the RV32F operations.

Arithmetic is done on exact rationals (fractions.Fraction) and rounded to
IEEE-754 binary32 with all five RISC-V rounding modes, producing the
RISC-V fflags (NV DZ OF UF NX, tininess detected after rounding).

Usage:
    python fpu_ref.py selftest            # cross-check RNE results against NumPy
    python fpu_ref.py vectors OUT [N]     # write N random vectors per op/rm (default 300)

Vector file format (one test per line, hex fields):
    op rm a b c x expected_result expected_flags
"""
import math
import random
import struct
import sys
from fractions import Fraction

# Operation codes shared with rtl/fpu_unit.sv
OPS = {
    "FADD": 0, "FSUB": 1, "FMUL": 2, "FDIV": 3, "FSQRT": 4,
    "FMIN": 5, "FMAX": 6, "FSGNJ": 7, "FSGNJN": 8, "FSGNJX": 9,
    "FEQ": 10, "FLT": 11, "FLE": 12, "FCLASS": 13,
    "FCVT_W_S": 14, "FCVT_WU_S": 15, "FCVT_S_W": 16, "FCVT_S_WU": 17,
    "FMV_X_W": 18, "FMV_W_X": 19,
    "FMADD": 20, "FMSUB": 21, "FNMSUB": 22, "FNMADD": 23,
}
RNE, RTZ, RDN, RUP, RMM = 0, 1, 2, 3, 4
NV, DZ, OF, UF, NX = 16, 8, 4, 2, 1
CANON_NAN = 0x7FC00000
MAX_FINITE = Fraction((2 ** 24 - 1) * 2 ** 104)


# ---------------------------------------------------------------- decoding
def fields(b):
    return (b >> 31) & 1, (b >> 23) & 0xFF, b & 0x7FFFFF


def is_nan(b):
    _, e, m = fields(b)
    return e == 0xFF and m != 0


def is_snan(b):
    return is_nan(b) and not (b >> 22) & 1


def is_inf(b):
    _, e, m = fields(b)
    return e == 0xFF and m == 0


def is_zero(b):
    return (b & 0x7FFFFFFF) == 0


def value(b):
    """Exact value of a finite float."""
    s, e, m = fields(b)
    v = Fraction(m, 2 ** 149) if e == 0 else Fraction(0x800000 | m, 2 ** 23) * Fraction(2) ** (e - 127)
    return -v if s else v


def sign(b):
    return (b >> 31) & 1


# ---------------------------------------------------------------- rounding
def floor_log2(a):
    """floor(log2(a)) for a positive Fraction."""
    e = a.numerator.bit_length() - a.denominator.bit_length()
    if Fraction(2) ** e > a:
        e -= 1
    elif Fraction(2) ** (e + 1) <= a:
        e += 1
    return e


def round_int(n, rm, s):
    """Round a non-negative Fraction n to an integer for sign s."""
    fl = n.numerator // n.denominator
    rem = n - fl
    if rem == 0:
        return fl, False
    if rm == RNE:
        up = rem > Fraction(1, 2) or (rem == Fraction(1, 2) and fl % 2 == 1)
    elif rm == RTZ:
        up = False
    elif rm == RDN:
        up = s == 1
    elif rm == RUP:
        up = s == 0
    else:  # RMM
        up = rem >= Fraction(1, 2)
    return fl + (1 if up else 0), True


def round_f32(v, rm, zero_sign=0):
    """Round an exact Fraction to binary32. Returns (bits, flags)."""
    if v == 0:
        return zero_sign << 31, 0
    s = 1 if v < 0 else 0
    a = -v if s else v
    e = floor_log2(a)
    eq = max(e, -126)
    n, inexact = round_int(a / Fraction(2) ** (eq - 23), rm, s)
    if n == 2 ** 24:
        n, eq = 2 ** 23, eq + 1
    flags = NX if inexact else 0
    if eq > 127:
        to_inf = rm in (RNE, RMM) or (rm == RUP and s == 0) or (rm == RDN and s == 1)
        return (s << 31) | (0x7F800000 if to_inf else 0x7F7FFFFF), OF | NX
    # Tininess after rounding: round to 24 bits with an unbounded exponent
    if e < -126 and inexact:
        nu, _ = round_int(a / Fraction(2) ** (e - 23), rm, s)
        tiny = not (e == -127 and nu == 2 ** 24)
        if tiny:
            flags |= UF
    if n < 2 ** 23:  # subnormal (eq == -126)
        return (s << 31) | n, flags
    return (s << 31) | ((eq + 127) << 23) | (n - 2 ** 23), flags


# ---------------------------------------------------------------- operations
def nan_result(*bs):
    return CANON_NAN, (NV if any(is_snan(b) for b in bs) else 0)


def fma(a, b, c, neg_prod, neg_c, has_c, rm):
    ops = (a, b, c) if has_c else (a, b)
    if (is_inf(a) and is_zero(b)) or (is_zero(a) and is_inf(b)):
        return CANON_NAN, NV
    if any(is_nan(x) for x in ops):
        return nan_result(*ops)
    sp = sign(a) ^ sign(b) ^ neg_prod
    sc = (sign(c) ^ neg_c) if has_c else 0
    if is_inf(a) or is_inf(b):
        if has_c and is_inf(c) and sp != sc:
            return CANON_NAN, NV
        return (sp << 31) | 0x7F800000, 0
    if has_c and is_inf(c):
        return (sc << 31) | 0x7F800000, 0
    p = value(a) * value(b)
    if neg_prod:
        p = -p
    if not has_c:
        return round_f32(p, rm, zero_sign=sp)
    cv = value(c)
    if neg_c:
        cv = -cv
    r = p + cv
    if r == 0:
        # exact zero: same-sign zeros keep the sign, otherwise +0 (-0 for RDN)
        if (p == 0 and cv == 0 and sp == sc):
            zs = sp
        else:
            zs = 1 if rm == RDN else 0
        return zs << 31, 0
    return round_f32(r, rm)


def fdiv(a, b, rm):
    if is_nan(a) or is_nan(b):
        return nan_result(a, b)
    s = sign(a) ^ sign(b)
    if (is_zero(a) and is_zero(b)) or (is_inf(a) and is_inf(b)):
        return CANON_NAN, NV
    if is_inf(a):
        return (s << 31) | 0x7F800000, 0
    if is_inf(b):
        return s << 31, 0
    if is_zero(b):
        return (s << 31) | 0x7F800000, DZ
    if is_zero(a):
        return s << 31, 0
    return round_f32(value(a) / value(b), rm)


def fsqrt(a, rm):
    if is_nan(a):
        return nan_result(a)
    if is_zero(a):
        return a, 0
    if sign(a):
        return CANON_NAN, NV
    if is_inf(a):
        return a, 0
    v = value(a)
    # sqrt(v) = sqrt(num/den); scale to an integer with plenty of extra bits
    k = 200
    scaled = v * Fraction(2) ** (2 * k)
    n = scaled.numerator // scaled.denominator
    r = math.isqrt(n)
    exact = (r * r == n) and (scaled.denominator == 1)
    # r has >> 26 significant bits, so r + 1/2 never lands on a rounding boundary
    approx = Fraction(r) if exact else Fraction(2 * r + 1, 2)
    return round_f32(approx / Fraction(2) ** k, rm)


def lt(a, b):
    """a < b for non-NaN values, with -0 == +0."""
    if is_zero(a) and is_zero(b):
        return False
    return value(a) < value(b)


def fminmax(a, b, is_max):
    flags = NV if (is_snan(a) or is_snan(b)) else 0
    if is_nan(a) and is_nan(b):
        return CANON_NAN, flags
    if is_nan(a):
        return b, flags
    if is_nan(b):
        return a, flags
    if is_zero(a) and is_zero(b):
        # -0 < +0 for FMIN/FMAX
        pick_a = (sign(a) == 0) if is_max else (sign(a) == 1)
        return (a if pick_a else b), flags
    a_lt_b = lt(a, b)
    return (b if a_lt_b else a) if is_max else (a if a_lt_b else b), flags


def fclass(a):
    s, e, m = fields(a)
    if is_inf(a):
        return 1 << (0 if s else 7)
    if is_nan(a):
        return 1 << (8 if is_snan(a) else 9)
    if is_zero(a):
        return 1 << (3 if s else 4)
    if e == 0:
        return 1 << (2 if s else 5)
    return 1 << (1 if s else 6)


def fcvt_to_int(a, rm, unsigned):
    if is_nan(a):
        return (0xFFFFFFFF if unsigned else 0x7FFFFFFF), NV
    if is_inf(a):
        if unsigned:
            return (0 if sign(a) else 0xFFFFFFFF), NV
        return (0x80000000 if sign(a) else 0x7FFFFFFF), NV
    v = value(a)
    s = 1 if v < 0 else 0
    mag, inexact = round_int(-v if s else v, rm, s)
    r = -mag if s else mag
    lo, hi = (0, 2 ** 32 - 1) if unsigned else (-2 ** 31, 2 ** 31 - 1)
    if r < lo or r > hi:
        if unsigned:
            return (0 if s else 0xFFFFFFFF), NV
        return (0x80000000 if s else 0x7FFFFFFF), NV
    return r & 0xFFFFFFFF, (NX if inexact else 0)


def fcvt_from_int(x, rm, unsigned):
    v = x if unsigned else (x - 2 ** 32 if x & 0x80000000 else x)
    return round_f32(Fraction(v), rm)


def execute(op, rm, a, b, c, x):
    """Return (result, flags) for one operation."""
    if op == OPS["FADD"]:
        return fma(a, 0x3F800000, b, 0, 0, True, rm)
    if op == OPS["FSUB"]:
        return fma(a, 0x3F800000, b, 0, 1, True, rm)
    if op == OPS["FMUL"]:
        return fma(a, b, 0, 0, 0, False, rm)
    if op == OPS["FDIV"]:
        return fdiv(a, b, rm)
    if op == OPS["FSQRT"]:
        return fsqrt(a, rm)
    if op == OPS["FMIN"]:
        return fminmax(a, b, False)
    if op == OPS["FMAX"]:
        return fminmax(a, b, True)
    if op == OPS["FSGNJ"]:
        return (b & 0x80000000) | (a & 0x7FFFFFFF), 0
    if op == OPS["FSGNJN"]:
        return (~b & 0x80000000) | (a & 0x7FFFFFFF), 0
    if op == OPS["FSGNJX"]:
        return ((a ^ b) & 0x80000000) | (a & 0x7FFFFFFF), 0
    if op == OPS["FEQ"]:
        if is_nan(a) or is_nan(b):
            return 0, (NV if (is_snan(a) or is_snan(b)) else 0)
        return int(a == b or (is_zero(a) and is_zero(b))), 0
    if op in (OPS["FLT"], OPS["FLE"]):
        if is_nan(a) or is_nan(b):
            return 0, NV
        if op == OPS["FLT"]:
            return int(lt(a, b)), 0
        return int(lt(a, b) or a == b or (is_zero(a) and is_zero(b))), 0
    if op == OPS["FCLASS"]:
        return fclass(a), 0
    if op == OPS["FCVT_W_S"]:
        return fcvt_to_int(a, rm, False)
    if op == OPS["FCVT_WU_S"]:
        return fcvt_to_int(a, rm, True)
    if op == OPS["FCVT_S_W"]:
        return fcvt_from_int(x, rm, False)
    if op == OPS["FCVT_S_WU"]:
        return fcvt_from_int(x, rm, True)
    if op == OPS["FMV_X_W"]:
        return a, 0
    if op == OPS["FMV_W_X"]:
        return x, 0
    if op == OPS["FMADD"]:
        return fma(a, b, c, 0, 0, True, rm)
    if op == OPS["FMSUB"]:
        return fma(a, b, c, 0, 1, True, rm)
    if op == OPS["FNMSUB"]:
        return fma(a, b, c, 1, 0, True, rm)
    if op == OPS["FNMADD"]:
        return fma(a, b, c, 1, 1, True, rm)
    raise ValueError(op)


# ---------------------------------------------------------------- operands
SPECIALS = [
    0x00000000, 0x80000000, 0x00000001, 0x80000001, 0x007FFFFF, 0x807FFFFF,
    0x00800000, 0x80800000, 0x3F800000, 0xBF800000, 0x40000000, 0x3F000000,
    0x7F7FFFFF, 0xFF7FFFFF, 0x7F800000, 0xFF800000, 0x7FC00000, 0x7F800001,
    0xFFC00000, 0x7FA00000, 0x4B000000, 0x4F000000, 0xCF000000, 0x4F800000,
    0x3EAAAAAB, 0x00400000, 0x34000000, 0x3F7FFFFF, 0x3F800001,
]
INT_SPECIALS = [0, 1, 0xFFFFFFFF, 0x7FFFFFFF, 0x80000000, 0x00FFFFFF, 0x01000001, 0xFFFFFF00, 12345]


def rand_float(rng):
    r = rng.random()
    if r < 0.15:
        return rng.choice(SPECIALS)
    if r < 0.30:  # subnormals and tiny normals
        return (rng.getrandbits(1) << 31) | (rng.randint(0, 2) << 23) | rng.getrandbits(23)
    if r < 0.45:  # huge values near overflow
        return (rng.getrandbits(1) << 31) | (rng.randint(250, 254) << 23) | rng.getrandbits(23)
    if r < 0.75:  # moderate exponents (more cancellation / interesting rounding)
        return (rng.getrandbits(1) << 31) | (rng.randint(120, 134) << 23) | rng.getrandbits(23)
    return rng.getrandbits(32)


def rand_close(rng, a):
    """A value close to a (to provoke cancellation)."""
    if is_nan(a) or is_inf(a):
        return rand_float(rng)
    d = rng.choice([0, 1, 2, 3, rng.getrandbits(8)])
    return (a ^ 0x80000000) + rng.choice([-d, d]) & 0xFFFFFFFF


def selftest(n=20000):
    import numpy as np
    rng = random.Random(1)
    bad = 0
    for _ in range(n):
        a, b = rand_float(rng), rand_float(rng)
        if rng.random() < 0.3:
            b = rand_close(rng, a)
        fa, fb = np.frombuffer(struct.pack("<II", a, b), dtype=np.float32)
        with np.errstate(all="ignore"):
            checks = [("FADD", fa + fb), ("FSUB", fa - fb), ("FMUL", fa * fb), ("FDIV", fa / fb),
                      ("FSQRT", np.sqrt(fa))]
        for name, ref in checks:
            rb = struct.unpack("<I", np.float32(ref).tobytes())[0]
            got, _ = execute(OPS[name], RNE, a, b, 0, 0)
            if is_nan(rb) and is_nan(got):
                continue
            if got != rb:
                bad += 1
                if bad < 10:
                    print(f"MISMATCH {name} {a:08x} {b:08x}: model {got:08x} numpy {rb:08x}")
    print(f"selftest: {n} operand pairs x 5 ops, {bad} mismatches against NumPy (RNE)")
    return bad


def vectors(path, n):
    rng = random.Random(2024)
    lines = []
    rounding_ops = {"FADD", "FSUB", "FMUL", "FDIV", "FSQRT", "FCVT_W_S", "FCVT_WU_S",
                    "FCVT_S_W", "FCVT_S_WU", "FMADD", "FMSUB", "FNMSUB", "FNMADD"}
    for name, op in OPS.items():
        rms = range(5) if name in rounding_ops else [0]
        for rm in rms:
            cases = []
            for s1 in SPECIALS:
                for s2 in (SPECIALS[::3] if name not in ("FSQRT", "FCLASS", "FMV_X_W") else [0]):
                    cases.append((s1, s2, rng.choice(SPECIALS), rng.choice(INT_SPECIALS)))
            for _ in range(n):
                a = rand_float(rng)
                b = rand_close(rng, a) if rng.random() < 0.25 else rand_float(rng)
                c = rand_float(rng)
                if name in ("FMADD", "FMSUB", "FNMSUB", "FNMADD") and rng.random() < 0.3:
                    # make the addend nearly cancel the product
                    p, _ = execute(OPS["FMUL"], RNE, a, b, 0, 0)
                    c = rand_close(rng, p)
                x = rng.choice(INT_SPECIALS) if rng.random() < 0.2 else rng.getrandbits(32)
                if rng.random() < 0.3:
                    x &= (1 << rng.randint(1, 31)) - 1
                cases.append((a, b, c, x))
            for a, b, c, x in cases:
                res, fl = execute(op, rm, a, b, c, x)
                lines.append(f"{op:02x} {rm:x} {a:08x} {b:08x} {c:08x} {x:08x} {res:08x} {fl:02x}")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {len(lines)} vectors to {path}")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "selftest":
        sys.exit(1 if selftest() else 0)
    if len(sys.argv) >= 3 and sys.argv[1] == "vectors":
        vectors(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 300)
        sys.exit(0)
    print(__doc__)
