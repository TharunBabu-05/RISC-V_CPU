# Floating-Point (RV32F) and Vector (RVV subset) Units

Both units live in the research core (`rtl/cpu_top.sv`, parameters `HAS_FPU` / `HAS_VEC`, default on).
The FPGA SoC core (`phase8/rtl/cpu_top_soc.sv`) builds **neither** by default: `HAS_FPU = 0` (optional,
works on the BRAM bus when enabled) and no vector unit (its bus has no vector load/store path). With a unit
absent, its opcodes and CSRs raise illegal-instruction exceptions and `misa` does not advertise it.

## RV32F — `rtl/fpu_unit.sv`

Full RV32F instruction set, IEEE-754 binary32:

| Group | Instructions |
|---|---|
| Arithmetic | `FADD.S` `FSUB.S` `FMUL.S` `FDIV.S` `FSQRT.S` |
| Fused | `FMADD.S` `FMSUB.S` `FNMSUB.S` `FNMADD.S` (single rounding) |
| Min/max, sign | `FMIN.S` `FMAX.S` (IEEE 754-2019 minimumNumber/maximumNumber), `FSGNJ[N\|X].S` |
| Compare, classify | `FEQ.S` (quiet) `FLT.S` `FLE.S` (signaling) `FCLASS.S` |
| Convert, move | `FCVT.W[U].S` `FCVT.S.W[U]` (saturating, NaN → max) `FMV.X.W` `FMV.W.X` |
| Load/store | `FLW` `FSW` |

- All five rounding modes (RNE, RTZ, RDN, RUP, RMM) plus dynamic (`frm`). Reserved static modes (101/110)
  and an invalid `frm` under DYN raise illegal-instruction.
- Subnormals in and out, canonical NaN results, fflags `NV DZ OF UF NX` with **tininess detected after
  rounding** (as RISC-V specifies).
- One exact multiply-add datapath serves FADD/FSUB/FMUL and the fused ops; FDIV/FSQRT use radix-2 digit
  recurrences (27 iterations), so no large combinational divider is built. Latency: 2 cycles, 30 for FDIV/FSQRT.
- `fcsr = {frm, fflags}`, `fflags` accumulates, `mstatus.FS` is implemented: `FS = Off` makes every F
  instruction and FP CSR illegal; any FP state change sets `FS = Dirty` and `mstatus.SD`.
- `f0` is an ordinary register. The FP register file has three read ports (FMA).
- Pipeline: FP results reach later instructions through the register-file write-through bypass, so a reader
  waits in ID while the producer is in EX or MEM (interlock); integer results (FEQ, FCVT.W, FMV.X.W, ...) use
  the normal integer forwarding.

## RVV 1.0 subset — `rtl/vector_unit.sv`

VLEN = 128, ELEN = 32, LMUL = 1, SEW = 8/16/32. Real RVV 1.0 encodings:

| Group | Instructions |
|---|---|
| Configuration | `vsetvli` `vsetivli` `vsetvl` (vl = min(AVL, VLMAX); unsupported vtype → `vill`, vl = 0) |
| Loads/stores | `vle8/16/32.v` `vse8/16/32.v` (unit stride, EEW must equal SEW, masked or unmasked) |
| Integer | `vadd` `vsub` `vrsub` `vand` `vor` `vxor` `vsll` `vsrl` `vsra` `vminu` `vmin` `vmaxu` `vmax` `vmul` |
| Compare → mask | `vmseq` `vmsne` `vmsltu` `vmslt` `vmsleu` `vmsle` `vmsgtu` `vmsgt` |
| Other | `vmerge.v[vxi]m` `vmv.v.[vxi]` `vredsum.vs` `vmv.x.s` `vmv.s.x` |

- `.vv` / `.vx` / `.vi` forms as the specification allows for each instruction.
- Masking with `v0`; tail and masked-off elements are left undisturbed (legal for both agnostic settings).
- CSRs: `vstart`, `vxsat`, `vxrm`, `vcsr`, and read-only `vl`, `vtype`, `vlenb` (= 16). `vtype` resets to
  `vill`, so vector instructions trap until the first `vset{i}vl{i}`.
- Vector instructions trap (illegal) when `vtype.vill` is set, when `vstart != 0`, when EEW ≠ SEW, or for any
  encoding outside the subset. Misaligned vector loads/stores raise address-misaligned exceptions.
- Loads/stores use a MEM-stage element sequencer in front of the D-cache (one element per access).
- This is **not** the full V extension (or a full Zve32x), so `misa.V` is not set.

## Verification

| Test | What it checks |
|---|---|
| `make sim_fpu_unit` | `fpu_unit` against 43,013 vectors from `tb/fpu_ref.py` (exact-rational reference, cross-checked with NumPy): every operation × every rounding mode, result bits and all five flags |
| `make sim_vector_unit` | `vector_unit` against 12,200 vectors from `tb/vec_ref.py`: every instruction form, SEW 8/16/32, random vl and masks |
| `make sim_fp` | RV32F through the pipeline: FS gating, FLW/FSW, dependent chains, FMA, conversions, dynamic rounding, fflags, illegal rounding modes |
| `make sim_vector` | RVV subset through the pipeline: vsetvl rules, loads/stores at each SEW, masking, reductions, tail handling, traps |

Both unit testbenches were also checked by injecting deliberate bugs (wrong tie rounding, dropped underflow
flag, masks ignored), which they report as failures.

## Known limits

- FP and vector units are sized for simulation in the research core; they are not timing-optimised for FPGA.
- No double precision (D), no vector floating point, no LMUL ≠ 1, strided/indexed/segment accesses,
  widening/narrowing, fixed-point (`vxrm`/`vxsat` exist but no instruction uses them).
- `mstatus.VS` is not implemented (vector instructions are not gated by it).
