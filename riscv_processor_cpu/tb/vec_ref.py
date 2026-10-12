"""
vec_ref.py - Reference model for the RVV 1.0 subset executed by vector_unit.sv.

Usage:
    python vec_ref.py vectors OUT [N]    # N random tests per instruction form (default 200)

Vector file format (one test per line, hex fields):
    instr sew vl scalar vs1 vs2 vd_old v0 expected_vd expected_scalar_out
(128-bit registers are written as 32 hex digits, element 0 in the low bits.)
"""
import random
import sys

VLEN = 128
OPIVV, OPMVV, OPIVI, OPIVX, OPMVX = 0b000, 0b010, 0b011, 0b100, 0b110

# (name, funct6, allowed funct3 categories)
FORMS = [
    ("vadd", 0b000000, [OPIVV, OPIVX, OPIVI]), ("vsub", 0b000010, [OPIVV, OPIVX]),
    ("vrsub", 0b000011, [OPIVX, OPIVI]), ("vminu", 0b000100, [OPIVV, OPIVX]),
    ("vmin", 0b000101, [OPIVV, OPIVX]), ("vmaxu", 0b000110, [OPIVV, OPIVX]),
    ("vmax", 0b000111, [OPIVV, OPIVX]), ("vand", 0b001001, [OPIVV, OPIVX, OPIVI]),
    ("vor", 0b001010, [OPIVV, OPIVX, OPIVI]), ("vxor", 0b001011, [OPIVV, OPIVX, OPIVI]),
    ("vsll", 0b100101, [OPIVV, OPIVX, OPIVI]), ("vsrl", 0b101000, [OPIVV, OPIVX, OPIVI]),
    ("vsra", 0b101001, [OPIVV, OPIVX, OPIVI]), ("vmerge", 0b010111, [OPIVV, OPIVX, OPIVI]),
    ("vmseq", 0b011000, [OPIVV, OPIVX, OPIVI]), ("vmsne", 0b011001, [OPIVV, OPIVX, OPIVI]),
    ("vmsltu", 0b011010, [OPIVV, OPIVX]), ("vmslt", 0b011011, [OPIVV, OPIVX]),
    ("vmsleu", 0b011100, [OPIVV, OPIVX, OPIVI]), ("vmsle", 0b011101, [OPIVV, OPIVX, OPIVI]),
    ("vmsgtu", 0b011110, [OPIVX, OPIVI]), ("vmsgt", 0b011111, [OPIVX, OPIVI]),
    ("vmul", 0b100101, [OPMVV, OPMVX]), ("vredsum", 0b000000, [OPMVV]),
    ("vmv.x.s", 0b010000, [OPMVV]), ("vmv.s.x", 0b010000, [OPMVX]),
]


def get(v, i, ew):
    return (v >> (i * ew)) & ((1 << ew) - 1)


def put(v, i, ew, x):
    m = ((1 << ew) - 1) << (i * ew)
    return (v & ~m) | ((x & ((1 << ew) - 1)) << (i * ew))


def signed(x, ew):
    return x - (1 << ew) if x >> (ew - 1) else x


def execute(name, f3, vm, imm5, sew, vl, scalar, vs1, vs2, vd, v0):
    ew = 8 << sew
    n = VLEN // ew
    mask = (1 << ew) - 1
    shift_op = name in ("vsll", "vsrl", "vsra")
    if f3 == OPIVI:
        bscal = (imm5 if shift_op else (imm5 - 32 if imm5 & 16 else imm5)) & mask
    else:
        bscal = scalar & mask
    res, sout = vd, 0
    if name == "vredsum":
        s = get(vs1, 0, ew)
        for i in range(min(n, vl)):
            if vm or (v0 >> i) & 1:
                s += get(vs2, i, ew)
        return (put(vd, 0, ew, s) if vl else vd), 0
    if name == "vmv.x.s":
        return vd, signed(get(vs2, 0, ew), ew) & 0xFFFFFFFF
    if name == "vmv.s.x":
        return (put(vd, 0, ew, scalar) if vl else vd), 0
    for i in range(n):
        body = i < vl
        active = body and (vm or (v0 >> i) & 1)
        a = get(vs2, i, ew)
        b = get(vs1, i, ew) if f3 in (OPIVV, OPMVV) else bscal
        sa, sb = signed(a, ew), signed(b, ew)
        sh = b & (ew - 1)
        if name.startswith("vms"):
            bit = {"vmseq": a == b, "vmsne": a != b, "vmsltu": a < b, "vmslt": sa < sb,
                   "vmsleu": a <= b, "vmsle": sa <= sb, "vmsgtu": a > b, "vmsgt": sa > sb}[name]
            if active:
                res = (res & ~(1 << i)) | (int(bit) << i)
            continue
        r = {"vadd": a + b, "vsub": a - b, "vrsub": b - a, "vminu": min(a, b), "vmaxu": max(a, b),
             "vmin": a if sa < sb else b, "vmax": a if sa > sb else b, "vand": a & b, "vor": a | b,
             "vxor": a ^ b, "vsll": a << sh, "vsrl": a >> sh, "vsra": (sa >> sh), "vmul": a * b,
             "vmerge": b if (vm or (v0 >> i) & 1) else a}[name]
        if name == "vmerge":
            if body:
                res = put(res, i, ew, r)
        elif active:
            res = put(res, i, ew, r)
    return res, sout


def encode(f6, vm, vs2, vs1, f3, vd):
    return (f6 << 26) | (vm << 25) | (vs2 << 20) | (vs1 << 15) | (f3 << 12) | (vd << 7) | 0b1010111


def vectors(path, n):
    rng = random.Random(7)
    lines = []
    for name, f6, cats in FORMS:
        for f3 in cats:
            for _ in range(n):
                sew = rng.choice([0, 1, 2])
                vlmax = VLEN // (8 << sew)
                vl = rng.choice([0, 1, vlmax, vlmax, rng.randint(0, vlmax)])
                vm = 1 if name in ("vmv.x.s", "vmv.s.x") else rng.choice([0, 1])
                rs1 = 0 if name == "vmv.x.s" else rng.getrandbits(5)
                vs2f = 0 if (name == "vmv.s.x" or (name == "vmerge" and vm)) else rng.getrandbits(5)
                regs = [rng.getrandbits(VLEN) for _ in range(4)]
                if rng.random() < 0.3:  # small / equal values to exercise compares and min/max
                    regs[1] = regs[0] if rng.random() < 0.5 else regs[1] & int("0F" * 16, 16)
                vs1, vs2, vd, v0 = regs
                scalar = rng.choice([0, 1, 0xFFFFFFFF, 0x80000000, 7, rng.getrandbits(32)])
                ins = encode(f6, vm, vs2f, rs1, f3, rng.getrandbits(5) | (0 if name.startswith("vms") else 1))
                res, sout = execute(name, f3, vm, rs1, sew, vl, scalar, vs1, vs2, vd, v0)
                lines.append(f"{ins:08x} {sew:x} {vl:08x} {scalar:08x} {vs1:032x} {vs2:032x} "
                             f"{vd:032x} {v0:032x} {res:032x} {sout:08x}")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {len(lines)} vectors to {path}")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "vectors":
        vectors(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 200)
        sys.exit(0)
    print(__doc__)
