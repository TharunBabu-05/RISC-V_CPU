// ============================================================
//  csr_file.sv  –  Minimal machine CSR file (Zicsr)
//  Implements a small subset of CSRs; unimplemented CSRs read as 0.
// ============================================================
`timescale 1ns/1ps

module csr_file #(
    parameter int XLEN = 32
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        csr_write,
    input  logic        trap_write,
    input  logic        mret_exec,
    input  logic        retire,
    input  logic [11:0] csr_addr,
    input  logic [XLEN-1:0] csr_wdata,
    input  logic [XLEN-1:0] trap_mepc,
    input  logic [XLEN-1:0] trap_mcause,
    input  logic [XLEN-1:0] trap_mip,
    output logic [XLEN-1:0] csr_rdata,
    // Additional outputs for interrupt_unit
    output logic [XLEN-1:0] mstatus_out,
    output logic [XLEN-1:0] mie_out,
    output logic [XLEN-1:0] mtvec_out,
    output logic [XLEN-1:0] mepc_out,
    output logic [XLEN-1:0] satp_out,
    output logic [XLEN-1:0] mcause_out
);
    // Machine CSRs (minimal subset)
    logic [XLEN-1:0] mstatus;   // 0x300
    logic [XLEN-1:0] mie;       // 0x304
    logic [XLEN-1:0] mtvec;     // 0x305
    logic [XLEN-1:0] mscratch;  // 0x340
    logic [XLEN-1:0] mepc;      // 0x341
    logic [XLEN-1:0] mcause;    // 0x342
    logic [XLEN-1:0] mip;       // 0x344
    logic [XLEN-1:0] satp;      // 0x180
    logic [XLEN-1:0] mcycle;    // 0xB00
    logic [XLEN-1:0] minstret;  // 0xB02
    logic [XLEN-1:0] fflags;    // 0x001
    logic [XLEN-1:0] frm;       // 0x002
    logic [XLEN-1:0] fcsr;      // 0x003
    logic [XLEN-1:0] vstart;    // 0x008
    logic [XLEN-1:0] vxsat;     // 0x009
    logic [XLEN-1:0] vxrm;      // 0x00A
    logic [XLEN-1:0] vl;        // 0xC20
    logic [XLEN-1:0] vtype;     // 0xC21

    // Write port (synchronous)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus  <= {XLEN{1'b0}};
            mie      <= {XLEN{1'b0}};
            mtvec    <= {XLEN{1'b0}};
            mscratch <= {XLEN{1'b0}};
            mepc     <= {XLEN{1'b0}};
            mcause   <= {XLEN{1'b0}};
            mip      <= {XLEN{1'b0}};
            satp     <= {XLEN{1'b0}};
            mcycle   <= {XLEN{1'b0}};
            minstret <= {XLEN{1'b0}};
            fflags   <= {XLEN{1'b0}};
            frm      <= {XLEN{1'b0}};
            fcsr     <= {XLEN{1'b0}};
            vstart   <= {XLEN{1'b0}};
            vxsat    <= {XLEN{1'b0}};
            vxrm     <= {XLEN{1'b0}};
            vl       <= {{(XLEN-3){1'b0}}, 3'd4};
            vtype    <= {XLEN{1'b0}};
        end else if (trap_write) begin
            mcycle <= mcycle + {{(XLEN-1){1'b0}}, 1'b1};
            if (retire)
                minstret <= minstret + {{(XLEN-1){1'b0}}, 1'b1};
            // Trap entry (M-mode): save context and mask MIE
            mepc   <= trap_mepc;
            mcause <= trap_mcause;
            mip    <= trap_mip;
            mstatus <= {{(XLEN-32){1'b0}}, mstatus[31:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};
        end else if (mret_exec) begin
            mcycle <= mcycle + {{(XLEN-1){1'b0}}, 1'b1};
            if (retire)
                minstret <= minstret + {{(XLEN-1){1'b0}}, 1'b1};
            // MRET: MIE <= MPIE; MPIE <= 1
            mstatus <= {{(XLEN-32){1'b0}}, mstatus[31:8], 1'b1, mstatus[6:4], mstatus[7], mstatus[2:0]};
        end else begin
            mcycle <= mcycle + {{(XLEN-1){1'b0}}, 1'b1};
            if (retire)
                minstret <= minstret + {{(XLEN-1){1'b0}}, 1'b1};
            if (csr_write) begin
            case (csr_addr)
                12'h300: mstatus  <= csr_wdata;
                12'h304: mie      <= csr_wdata;
                12'h305: mtvec    <= csr_wdata;
                12'h340: mscratch <= csr_wdata;
                12'h341: mepc     <= csr_wdata;
                12'h342: mcause   <= csr_wdata;
                12'h344: mip      <= csr_wdata;
                12'h180: satp     <= csr_wdata;
                12'hB00: mcycle   <= csr_wdata;
                12'hB02: minstret <= csr_wdata;
                12'h001: fflags   <= csr_wdata;
                12'h002: frm      <= csr_wdata;
                12'h003: fcsr     <= csr_wdata;
                12'h008: vstart   <= csr_wdata;
                12'h009: vxsat    <= csr_wdata;
                12'h00A: vxrm     <= csr_wdata;
                12'hC20: vl       <= csr_wdata;
                12'hC21: vtype    <= csr_wdata;
                default: ; // unimplemented CSR
            endcase
            end
        end
    end

    // Read port (combinational)
    always_comb begin
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h304: csr_rdata = mie;
            12'h305: csr_rdata = mtvec;
            12'h340: csr_rdata = mscratch;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h344: csr_rdata = mip;
            12'h180: csr_rdata = satp;
            12'hB00: csr_rdata = mcycle;
            12'hB02: csr_rdata = minstret;
            12'h001: csr_rdata = fflags;
            12'h002: csr_rdata = frm;
            12'h003: csr_rdata = fcsr;
            12'h008: csr_rdata = vstart;
            12'h009: csr_rdata = vxsat;
            12'h00A: csr_rdata = vxrm;
            12'hC20: csr_rdata = vl;
            12'hC21: csr_rdata = vtype;
            default: csr_rdata = {XLEN{1'b0}};
        endcase
    end
    
    // Additional read ports for interrupt_unit
    assign mstatus_out = mstatus;
    assign mie_out = mie;
    assign mtvec_out = mtvec;
    assign mepc_out = mepc;
    assign satp_out = satp;
    assign mcause_out = mcause;

endmodule
