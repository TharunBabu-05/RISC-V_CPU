// ============================================================
//  csr_file.sv  –  Machine/supervisor CSR file (Zicsr)
//
//  Accessing a CSR that does not exist, from too low a privilege
//  level, or writing a read-only CSR is reported on csr_illegal and
//  raises an illegal-instruction exception in the pipeline.
//
//  sstatus is a restricted view of mstatus. mip merges software-writable
//  supervisor pending bits with live platform interrupt inputs. cycle/instret
//  are 64-bit counters
//  (upper halves via the *h CSRs on RV32).
//
//  M, S and U privilege levels are implemented, including delegated traps,
//  supervisor returns and the supervisor CSR aliases.
//
//  Debug triggers (Sdtrig) are implemented with zero triggers: tselect,
//  tdata1/2/3 read as zero (tdata1.type = 0, "no trigger").
//
//  HAS_FPU: fflags/frm/fcsr exist, misa.F is set, and mstatus.FS
//           gates them (FS = Off makes them illegal; any FP state
//           change marks FS Dirty, reflected in mstatus.SD).
//  HAS_VEC: vstart/vxsat/vxrm/vcsr and the read-only vl/vtype/vlenb
//           exist; vl and vtype change only through vset{i}vl{i}.
// ============================================================
`timescale 1ns/1ps

module csr_file #(
    parameter int XLEN = 32,
    parameter bit HAS_FPU = 1'b1,
    parameter bit HAS_VEC = 1'b1,
    parameter int VLEN    = 128
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        csr_write,
    input  logic        trap_write,
    input  logic        trap_to_s,
    input  logic        mret_exec,
    input  logic        sret_exec,
    input  logic        retire,
    input  logic [11:0] csr_addr,
    input  logic [XLEN-1:0] csr_wdata,
    input  logic        csr_write_attempt,   // instruction would write (for legality)
    input  logic [XLEN-1:0] trap_mepc,
    input  logic [XLEN-1:0] trap_mcause,
    input  logic [XLEN-1:0] trap_mtval,
    input  logic [XLEN-1:0] trap_mip,        // live pending interrupts (MEIP = bit 11)
    // Floating-point state updates from the FPU
    input  logic        fflags_set_valid,
    input  logic [4:0]  fflags_set,
    input  logic        fs_dirty,           // an F instruction changed FP state
    // Vector configuration updates (vset{i}vl{i})
    input  logic        vcfg_write,
    input  logic [XLEN-1:0] vcfg_vl,
    input  logic [XLEN-1:0] vcfg_vtype,
    output logic [XLEN-1:0] csr_rdata,
    output logic        csr_illegal,
    output logic [2:0]      frm_out,
    output logic [XLEN-1:0] vl_out,
    output logic [XLEN-1:0] vtype_out,
    output logic [XLEN-1:0] vstart_out,
    // Additional outputs for interrupt_unit
    output logic [XLEN-1:0] mstatus_out,
    output logic [XLEN-1:0] mie_out,
    output logic [XLEN-1:0] mip_out,
    output logic [XLEN-1:0] mtvec_out,
    output logic [XLEN-1:0] stvec_out,
    output logic [XLEN-1:0] mepc_out,
    output logic [XLEN-1:0] sepc_out,
    output logic [XLEN-1:0] satp_out,
    output logic [1:0]      current_priv_out,
    output logic [XLEN-1:0] mcause_out,
    output logic [XLEN-1:0] mideleg_out,
    output logic [XLEN-1:0] medeleg_out,
    output logic [31:0]     pmpcfg0_out,
    output logic [XLEN-1:0] pmpaddr0_out,
    output logic [XLEN-1:0] pmpaddr1_out,
    output logic [XLEN-1:0] pmpaddr2_out,
    output logic [XLEN-1:0] pmpaddr3_out
);
    // Machine CSRs
    logic [XLEN-1:0] mstatus;   // 0x300 (sstatus 0x100 is a view)
    logic [XLEN-1:0] medeleg;   // 0x302
    logic [XLEN-1:0] mideleg;   // 0x303
    logic [XLEN-1:0] mie;       // 0x304
    logic [XLEN-1:0] mtvec;     // 0x305
    logic [XLEN-1:0] mcounteren;// 0x306
    logic [XLEN-1:0] scounteren;// 0x106
    logic [XLEN-1:0] mscratch;  // 0x340
    logic [XLEN-1:0] mepc;      // 0x341
    logic [XLEN-1:0] mcause;    // 0x342
    logic [XLEN-1:0] mtval;     // 0x343
    logic [XLEN-1:0] mip_sw;    // 0x344 software-writable bits
    // Supervisor CSRs
    logic [XLEN-1:0] stvec;     // 0x105
    logic [XLEN-1:0] sscratch;  // 0x140
    logic [XLEN-1:0] sepc;      // 0x141
    logic [XLEN-1:0] scause;    // 0x142
    logic [XLEN-1:0] stval;     // 0x143
    logic [XLEN-1:0] satp;      // 0x180
    logic [31:0]     pmpcfg0;   // 0x3A0, four RV32 configuration bytes
    logic [XLEN-1:0] pmpaddr0, pmpaddr1, pmpaddr2, pmpaddr3;
    // Counters (64-bit on every XLEN)
    logic [63:0]     mcycle;    // 0xB00 / 0xB80, cycle 0xC00 / 0xC80
    logic [63:0]     minstret;  // 0xB02 / 0xB82, instret 0xC02 / 0xC82
    // Floating-point CSRs (fcsr 0x003 = {frm, fflags})
    logic [4:0]      fflags;    // 0x001
    logic [2:0]      frm;       // 0x002
    // Vector CSRs (vcsr 0x00F = {vxrm, vxsat})
    logic [XLEN-1:0] vstart;    // 0x008
    logic            vxsat;     // 0x009
    logic [1:0]      vxrm;      // 0x00A
    logic [XLEN-1:0] vl;        // 0xC20 (read-only)
    logic [XLEN-1:0] vtype;     // 0xC21 (read-only)
    logic [1:0]      current_priv;

    localparam logic [1:0] PRIV_U = 2'b00;
    localparam logic [1:0] PRIV_S = 2'b01;
    localparam logic [1:0] PRIV_M = 2'b11;

    // misa: MXL (1 = 32-bit, 2 = 64-bit) and extensions I, M (+ F).
    // The vector unit implements an RVV subset, so misa.V is not set.
    localparam logic [25:0] MISA_EXT = 26'h0001100 | (HAS_FPU ? 26'h0000020 : 26'h0);
    localparam logic [XLEN-1:0] MISA_VAL =
        {((XLEN == 64) ? 2'b10 : 2'b01), {(XLEN-28){1'b0}}, MISA_EXT};

    // sstatus exposes SIE, SPIE, SPP, FS, SUM, MXR (and SD) of mstatus
    localparam logic [XLEN-1:0] SSTATUS_MASK =
        {1'b1, {(XLEN-32){1'b0}}, 31'h000C_6122};

    logic [XLEN-1:0] mip_rd, mstatus_rd;
    assign mip_rd = mip_sw | trap_mip;
    // SD summarises a Dirty FS field
    assign mstatus_rd = {(mstatus[14:13] == 2'b11), mstatus[XLEN-2:0]};

    logic fp_csr;
    assign fp_csr = (csr_addr == 12'h001) || (csr_addr == 12'h002) || (csr_addr == 12'h003);

    // ---------------- Legality ----------------
    logic csr_exists, counter_csr, counter_ok;
    always_comb begin
        case (csr_addr)
            12'h001, 12'h002, 12'h003:
                csr_exists = HAS_FPU;
            12'h008, 12'h009, 12'h00A, 12'h00F, 12'hC20, 12'hC21, 12'hC22:
                csr_exists = HAS_VEC;
            12'h100, 12'h104, 12'h105, 12'h106, 12'h140, 12'h141, 12'h142, 12'h143, 12'h144, 12'h180,
            12'h300, 12'h301, 12'h302, 12'h303, 12'h304, 12'h305, 12'h306,
            12'h340, 12'h341, 12'h342, 12'h343, 12'h344,
            12'h3A0, 12'h3B0, 12'h3B1, 12'h3B2, 12'h3B3,
            12'hB00, 12'hB02, 12'hC00, 12'hC02,
            12'hF11, 12'hF12, 12'hF13, 12'hF14, 12'hF15,
            12'h7A0, 12'h7A1, 12'h7A2, 12'h7A3:
                csr_exists = 1'b1;
            12'hB80, 12'hB82, 12'hC80, 12'hC82:
                csr_exists = (XLEN == 32);
            default:
                csr_exists = 1'b0;
        endcase
    end

    // User-level counters are gated by mcounteren below M-mode
    assign counter_csr = (csr_addr[11:5] == 7'b1100000) || (csr_addr[11:5] == 7'b1100100);
    assign counter_ok  = !counter_csr || (current_priv == PRIV_M) ||
                         (mcounteren[csr_addr[4:0]] &&
                          (current_priv == PRIV_S || scounteren[csr_addr[4:0]]));

    always_comb begin
        csr_illegal = !csr_exists ||
                      (current_priv < csr_addr[9:8]) ||
                      (csr_write_attempt && (csr_addr[11:10] == 2'b11)) ||   // read-only space
                      (fp_csr && (mstatus[14:13] == 2'b00)) ||                // FP state is Off
                      ((csr_addr == 12'h180) && current_priv == PRIV_S && mstatus[20]) ||
                      !counter_ok;
    end

    function automatic logic [7:0] pmpcfg_warl(input logic [7:0] value);
        begin
            // Bits 6:5 are reserved. W without R is a reserved permission
            // encoding, so clear W in that case.
            pmpcfg_warl = {value[7], 2'b00, value[4:3], value[2:0]};
            if (!value[0] && value[1])
                pmpcfg_warl[1] = 1'b0;
        end
    endfunction

    // ---------------- Write port ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus    <= {XLEN{1'b0}};
            medeleg    <= {XLEN{1'b0}};
            mideleg    <= {XLEN{1'b0}};
            mie        <= {XLEN{1'b0}};
            mtvec      <= {XLEN{1'b0}};
            mcounteren <= {XLEN{1'b0}};
            scounteren <= {XLEN{1'b0}};
            mscratch   <= {XLEN{1'b0}};
            mepc       <= {XLEN{1'b0}};
            mcause     <= {XLEN{1'b0}};
            mtval      <= {XLEN{1'b0}};
            mip_sw     <= {XLEN{1'b0}};
            stvec      <= {XLEN{1'b0}};
            sscratch   <= {XLEN{1'b0}};
            sepc       <= {XLEN{1'b0}};
            scause     <= {XLEN{1'b0}};
            stval      <= {XLEN{1'b0}};
            satp       <= {XLEN{1'b0}};
            pmpcfg0    <= 32'b0;
            pmpaddr0   <= {XLEN{1'b0}};
            pmpaddr1   <= {XLEN{1'b0}};
            pmpaddr2   <= {XLEN{1'b0}};
            pmpaddr3   <= {XLEN{1'b0}};
            mcycle     <= 64'b0;
            minstret   <= 64'b0;
            fflags     <= 5'd0;
            frm        <= 3'd0;
            vstart     <= {XLEN{1'b0}};
            vxsat      <= 1'b0;
            vxrm       <= 2'd0;
            vl         <= {XLEN{1'b0}};
            vtype      <= {1'b1, {(XLEN-1){1'b0}}};    // vill until the first vsetvl
            current_priv <= PRIV_M;
        end else begin
            // Counters. An instruction that writes a counter suppresses that
            // counter's increment; `retire` comes from the instruction leaving
            // EX, the same stage that reads and writes CSRs.
            if (!(csr_write && (csr_addr == 12'hB00 || csr_addr == 12'hB80)))
                mcycle <= mcycle + 64'd1;
            if (retire && !(csr_write && (csr_addr == 12'hB02 || csr_addr == 12'hB82)))
                minstret <= minstret + 64'd1;

            if (trap_write) begin
                if (trap_to_s) begin
                    sepc   <= trap_mepc;
                    scause <= trap_mcause;
                    stval  <= trap_mtval;
                    mstatus[8] <= (current_priv == PRIV_S);
                    mstatus[5] <= mstatus[1];
                    mstatus[1] <= 1'b0;
                    current_priv <= PRIV_S;
                end else begin
                    mepc   <= trap_mepc;
                    mcause <= trap_mcause;
                    mtval  <= trap_mtval;
                    mstatus[12:11] <= current_priv;
                    mstatus[7]     <= mstatus[3];
                    mstatus[3]     <= 1'b0;
                    current_priv   <= PRIV_M;
                end
            end else if (mret_exec) begin
                // MRET: MIE <= MPIE; MPIE <= 1; MPP <= U
                current_priv   <= mstatus[12:11];
                mstatus[3]     <= mstatus[7];
                mstatus[7]     <= 1'b1;
                mstatus[12:11] <= PRIV_U;
            end else if (sret_exec) begin
                // SRET: SIE <= SPIE; SPIE <= 1; SPP <= U
                current_priv <= mstatus[8] ? PRIV_S : PRIV_U;
                mstatus[1]   <= mstatus[5];
                mstatus[5]   <= 1'b1;
                mstatus[8]   <= 1'b0;
            end else if (csr_write) begin
                case (csr_addr)
                    12'h100: mstatus  <= (mstatus & ~SSTATUS_MASK) | (csr_wdata & SSTATUS_MASK);
                    12'h104: mie      <= (mie & ~mideleg) | (csr_wdata & mideleg);
                    12'h105: stvec    <= csr_wdata;
                    12'h106: scounteren <= csr_wdata;
                    12'h140: sscratch <= csr_wdata;
                    12'h141: sepc     <= {csr_wdata[XLEN-1:2], 2'b00};
                    12'h142: scause   <= csr_wdata;
                    12'h143: stval    <= csr_wdata;
                    12'h144: mip_sw   <= (mip_sw & ~mideleg) |
                                             (csr_wdata & mideleg & {{(XLEN-2){1'b0}}, 2'b10});
                    12'h180: satp     <= csr_wdata;
                    // MPP is WARL: 10 is reserved; U, S and M are supported.
                    12'h300: mstatus  <= {csr_wdata[XLEN-1:13],
                                          (csr_wdata[12:11] == 2'b10) ? 2'b00 : csr_wdata[12:11],
                                          csr_wdata[10:0]};
                    12'h302: medeleg  <= csr_wdata;
                    12'h303: mideleg  <= csr_wdata;
                    12'h304: mie      <= csr_wdata;
                    // mtvec MODE is WARL: only Direct (0) and Vectored (1) exist
                    12'h305: mtvec    <= {csr_wdata[XLEN-1:2], 1'b0, (csr_wdata[1:0] == 2'b01)};
                    12'h306: mcounteren <= csr_wdata;
                    12'h340: mscratch <= csr_wdata;
                    12'h341: mepc     <= {csr_wdata[XLEN-1:2], 2'b00};
                    12'h342: mcause   <= csr_wdata;
                    12'h343: mtval    <= csr_wdata;
                    12'h344: mip_sw   <= csr_wdata & {{(XLEN-10){1'b0}}, 10'h222};  // SSIP, STIP, SEIP
                    12'h3A0: begin
                        if (!pmpcfg0[7])  pmpcfg0[7:0]   <= pmpcfg_warl(csr_wdata[7:0]);
                        if (!pmpcfg0[15]) pmpcfg0[15:8]  <= pmpcfg_warl(csr_wdata[15:8]);
                        if (!pmpcfg0[23]) pmpcfg0[23:16] <= pmpcfg_warl(csr_wdata[23:16]);
                        if (!pmpcfg0[31]) pmpcfg0[31:24] <= pmpcfg_warl(csr_wdata[31:24]);
                    end
                    12'h3B0: if (!pmpcfg0[7] && !(pmpcfg0[15] && pmpcfg0[12:11] == 2'b01)) pmpaddr0 <= csr_wdata;
                    12'h3B1: if (!pmpcfg0[15] && !(pmpcfg0[23] && pmpcfg0[20:19] == 2'b01)) pmpaddr1 <= csr_wdata;
                    12'h3B2: if (!pmpcfg0[23] && !(pmpcfg0[31] && pmpcfg0[28:27] == 2'b01)) pmpaddr2 <= csr_wdata;
                    12'h3B3: if (!pmpcfg0[31]) pmpaddr3 <= csr_wdata;
                    12'hB00: if (XLEN == 64) mcycle <= csr_wdata; else mcycle[31:0] <= csr_wdata[31:0];
                    12'hB02: if (XLEN == 64) minstret <= csr_wdata; else minstret[31:0] <= csr_wdata[31:0];
                    12'hB80: mcycle[63:32]   <= csr_wdata[31:0];
                    12'hB82: minstret[63:32] <= csr_wdata[31:0];
                    12'h001: fflags   <= csr_wdata[4:0];
                    12'h002: frm      <= csr_wdata[2:0];
                    12'h003: begin frm <= csr_wdata[7:5]; fflags <= csr_wdata[4:0]; end
                    12'h008: vstart   <= csr_wdata & (VLEN/8 - 1);
                    12'h009: vxsat    <= csr_wdata[0];
                    12'h00A: vxrm     <= csr_wdata[1:0];
                    12'h00F: begin vxrm <= csr_wdata[2:1]; vxsat <= csr_wdata[0]; end
                    default: ; // read-only or unimplemented (flagged illegal)
                endcase
                if (fp_csr) mstatus[14:13] <= 2'b11;              // FP state written: Dirty
            end

            // Updates from the instruction in EX (never in the same cycle as a CSR write)
            if (fflags_set_valid)
                fflags <= fflags | fflags_set;
            if (fs_dirty)
                mstatus[14:13] <= 2'b11;
            if (vcfg_write) begin
                vl     <= vcfg_vl;
                vtype  <= vcfg_vtype;
                vstart <= {XLEN{1'b0}};
            end
        end
    end

    // ---------------- Read port (combinational) ----------------
    always_comb begin
        case (csr_addr)
            12'h100: csr_rdata = mstatus_rd & SSTATUS_MASK;
            12'h104: csr_rdata = mie & mideleg;
            12'h105: csr_rdata = stvec;
            12'h106: csr_rdata = scounteren;
            12'h140: csr_rdata = sscratch;
            12'h141: csr_rdata = sepc;
            12'h142: csr_rdata = scause;
            12'h143: csr_rdata = stval;
            12'h144: csr_rdata = mip_rd & mideleg;
            12'h180: csr_rdata = satp;
            12'h300: csr_rdata = mstatus_rd;
            12'h301: csr_rdata = MISA_VAL;
            12'h302: csr_rdata = medeleg;
            12'h303: csr_rdata = mideleg;
            12'h304: csr_rdata = mie;
            12'h305: csr_rdata = mtvec;
            12'h306: csr_rdata = mcounteren;
            12'h340: csr_rdata = mscratch;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h343: csr_rdata = mtval;
            12'h344: csr_rdata = mip_rd;
            12'h3A0: csr_rdata = {{(XLEN-32){1'b0}}, pmpcfg0};
            12'h3B0: csr_rdata = pmpaddr0;
            12'h3B1: csr_rdata = pmpaddr1;
            12'h3B2: csr_rdata = pmpaddr2;
            12'h3B3: csr_rdata = pmpaddr3;
            12'hB00, 12'hC00: csr_rdata = mcycle[XLEN-1:0];
            12'hB02, 12'hC02: csr_rdata = minstret[XLEN-1:0];
            12'hB80, 12'hC80: csr_rdata = {{(XLEN-32){1'b0}}, mcycle[63:32]};
            12'hB82, 12'hC82: csr_rdata = {{(XLEN-32){1'b0}}, minstret[63:32]};
            12'h001: csr_rdata = {{(XLEN-5){1'b0}}, fflags};
            12'h002: csr_rdata = {{(XLEN-3){1'b0}}, frm};
            12'h003: csr_rdata = {{(XLEN-8){1'b0}}, frm, fflags};
            12'h008: csr_rdata = vstart;
            12'h009: csr_rdata = {{(XLEN-1){1'b0}}, vxsat};
            12'h00A: csr_rdata = {{(XLEN-2){1'b0}}, vxrm};
            12'h00F: csr_rdata = {{(XLEN-3){1'b0}}, vxrm, vxsat};
            12'hC20: csr_rdata = vl;
            12'hC21: csr_rdata = vtype;
            12'hC22: csr_rdata = VLEN / 8;                        // vlenb
            // mvendorid, marchid, mimpid, mhartid, mconfigptr read as zero
            default: csr_rdata = {XLEN{1'b0}};
        endcase
    end

    // Additional read ports for interrupt_unit
    assign mstatus_out = mstatus_rd;
    assign frm_out     = frm;
    assign vl_out      = vl;
    assign vtype_out   = vtype;
    assign vstart_out  = vstart;
    assign mie_out = mie;
    assign mip_out = mip_rd;
    assign mtvec_out = mtvec;
    assign stvec_out = stvec;
    assign mepc_out = mepc;
    assign sepc_out = sepc;
    assign satp_out = satp;
    assign current_priv_out = current_priv;
    assign mcause_out = mcause;
    assign mideleg_out = mideleg;
    assign medeleg_out = medeleg;
    assign pmpcfg0_out = pmpcfg0;
    assign pmpaddr0_out = pmpaddr0;
    assign pmpaddr1_out = pmpaddr1;
    assign pmpaddr2_out = pmpaddr2;
    assign pmpaddr3_out = pmpaddr3;

endmodule
