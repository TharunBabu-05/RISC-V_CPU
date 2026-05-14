// ============================================================
//  mmu.sv  –  Simple Sv32 MMU (ITLB + DTLB + PTW)
// ============================================================
`timescale 1ns/1ps

module mmu #(
    parameter int XLEN = 32,
    parameter int TLB_ENTRIES = 8
) (
    input  logic            clk,
    input  logic            rst_n,

    input  logic [XLEN-1:0] satp,

    input  logic [XLEN-1:0] inst_vaddr,
    input  logic            inst_req,
    output logic [XLEN-1:0] inst_paddr,
    output logic            inst_ready,
    output logic            inst_fault,

    input  logic [XLEN-1:0] data_vaddr,
    input  logic            data_req,
    input  logic            data_write,
    output logic [XLEN-1:0] data_paddr,
    output logic            data_ready,
    output logic            data_fault,

    output logic            stall,

    output logic            ptw_read,
    output logic [XLEN-1:0] ptw_addr,
    input  logic [31:0]     ptw_rdata
);

    localparam int VPN_BITS = 20;
    localparam int PPN_BITS = 22;

    localparam logic [1:0] S_IDLE = 2'd0;
    localparam logic [1:0] S_L1   = 2'd1;
    localparam logic [1:0] S_L0   = 2'd2;

    logic satp_mode;
    logic [PPN_BITS-1:0] satp_ppn;
    logic mmu_en;

    assign satp_mode = satp[31];
    assign satp_ppn  = satp[PPN_BITS-1:0];
    assign mmu_en    = (XLEN == 32) && satp_mode;

    // ITLB/DTLB arrays
    logic               itlb_valid [0:TLB_ENTRIES-1];
    logic [VPN_BITS-1:0] itlb_vpn   [0:TLB_ENTRIES-1];
    logic [PPN_BITS-1:0] itlb_ppn   [0:TLB_ENTRIES-1];
    logic               itlb_r     [0:TLB_ENTRIES-1];
    logic               itlb_w     [0:TLB_ENTRIES-1];
    logic               itlb_x     [0:TLB_ENTRIES-1];
    logic               itlb_a     [0:TLB_ENTRIES-1];
    logic               itlb_d     [0:TLB_ENTRIES-1];

    logic               dtlb_valid [0:TLB_ENTRIES-1];
    logic [VPN_BITS-1:0] dtlb_vpn   [0:TLB_ENTRIES-1];
    logic [PPN_BITS-1:0] dtlb_ppn   [0:TLB_ENTRIES-1];
    logic               dtlb_r     [0:TLB_ENTRIES-1];
    logic               dtlb_w     [0:TLB_ENTRIES-1];
    logic               dtlb_x     [0:TLB_ENTRIES-1];
    logic               dtlb_a     [0:TLB_ENTRIES-1];
    logic               dtlb_d     [0:TLB_ENTRIES-1];

    logic [VPN_BITS-1:0] inst_vpn;
    logic [VPN_BITS-1:0] data_vpn;
    assign inst_vpn = inst_vaddr[31:12];
    assign data_vpn = data_vaddr[31:12];

    // TLB lookup
    logic itlb_hit;
    logic dtlb_hit;
    int unsigned itlb_idx;
    int unsigned dtlb_idx;

    always_comb begin
        itlb_hit = 1'b0;
        itlb_idx = 0;
        for (int i = 0; i < TLB_ENTRIES; i = i + 1) begin
            if (itlb_valid[i] && itlb_vpn[i] == inst_vpn) begin
                itlb_hit = 1'b1;
                itlb_idx = i;
            end
        end
    end

    always_comb begin
        dtlb_hit = 1'b0;
        dtlb_idx = 0;
        for (int i = 0; i < TLB_ENTRIES; i = i + 1) begin
            if (dtlb_valid[i] && dtlb_vpn[i] == data_vpn) begin
                dtlb_hit = 1'b1;
                dtlb_idx = i;
            end
        end
    end

    function automatic logic perm_ok(
        input logic is_inst,
        input logic is_store,
        input logic pte_r,
        input logic pte_w,
        input logic pte_x,
        input logic pte_a,
        input logic pte_d
    );
        begin
            if (!pte_a)
                perm_ok = 1'b0;
            else if (is_inst)
                perm_ok = pte_x;
            else if (is_store)
                perm_ok = pte_w && pte_d;
            else
                perm_ok = pte_r;
        end
    endfunction

    // PTW state
    logic [1:0] state;
    logic [XLEN-1:0] req_vaddr;
    logic            req_is_inst;
    logic            req_is_store;
    logic [PPN_BITS-1:0] l1_ppn_base;

    logic fault_pending;
    logic fault_is_inst;

    logic [PPN_BITS-1:0] itlb_ppn_hit;
    logic [PPN_BITS-1:0] dtlb_ppn_hit;
    logic itlb_perm_ok;
    logic dtlb_perm_ok;

    assign itlb_ppn_hit = itlb_ppn[itlb_idx];
    assign dtlb_ppn_hit = dtlb_ppn[dtlb_idx];

    assign itlb_perm_ok = perm_ok(1'b1, 1'b0,
                                 itlb_r[itlb_idx], itlb_w[itlb_idx], itlb_x[itlb_idx],
                                 itlb_a[itlb_idx], itlb_d[itlb_idx]);

    assign dtlb_perm_ok = perm_ok(1'b0, data_write,
                                 dtlb_r[dtlb_idx], dtlb_w[dtlb_idx], dtlb_x[dtlb_idx],
                                 dtlb_a[dtlb_idx], dtlb_d[dtlb_idx]);

    // Outputs default
    always_comb begin
        inst_paddr = inst_vaddr;
        data_paddr = data_vaddr;
        inst_ready = 1'b1;
        data_ready = 1'b1;
        inst_fault = 1'b0;
        data_fault = 1'b0;

        if (mmu_en) begin
            inst_ready = !inst_req || itlb_hit;
            data_ready = !data_req || dtlb_hit;

            if (inst_req && itlb_hit)
                inst_paddr = {itlb_ppn_hit, inst_vaddr[11:0]};
            if (data_req && dtlb_hit)
                data_paddr = {dtlb_ppn_hit, data_vaddr[11:0]};

            if (inst_req && itlb_hit && !itlb_perm_ok)
                inst_fault = 1'b1;
            if (data_req && dtlb_hit && !dtlb_perm_ok)
                data_fault = 1'b1;
        end

        if (fault_pending) begin
            inst_fault = fault_is_inst;
            data_fault = !fault_is_inst;
        end
    end

    assign stall = (state != S_IDLE);

    // PTW address generation
    logic [9:0] req_vpn0;
    logic [9:0] req_vpn1;
    assign req_vpn0 = req_vaddr[21:12];
    assign req_vpn1 = req_vaddr[31:22];

    always_comb begin
        ptw_read = 1'b0;
        ptw_addr = {XLEN{1'b0}};

        if (state == S_L1) begin
            ptw_read = 1'b1;
            ptw_addr = {satp_ppn, 12'b0} + ({{(XLEN-10){1'b0}}, req_vpn1} << 2);
        end else if (state == S_L0) begin
            ptw_read = 1'b1;
            ptw_addr = {l1_ppn_base, 12'b0} + ({{(XLEN-10){1'b0}}, req_vpn0} << 2);
        end
    end

    // TLB replacement pointers
    int unsigned itlb_wr_ptr;
    int unsigned dtlb_wr_ptr;

    // satp change detection (flush TLBs)
    logic [XLEN-1:0] satp_last;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            fault_pending <= 1'b0;
            fault_is_inst <= 1'b0;
            l1_ppn_base <= {PPN_BITS{1'b0}};
            req_vaddr <= {XLEN{1'b0}};
            req_is_inst <= 1'b0;
            req_is_store <= 1'b0;
            itlb_wr_ptr <= 0;
            dtlb_wr_ptr <= 0;
            satp_last <= {XLEN{1'b0}};
            for (int i = 0; i < TLB_ENTRIES; i = i + 1) begin
                itlb_valid[i] <= 1'b0;
                dtlb_valid[i] <= 1'b0;
                itlb_vpn[i] <= {VPN_BITS{1'b0}};
                dtlb_vpn[i] <= {VPN_BITS{1'b0}};
                itlb_ppn[i] <= {PPN_BITS{1'b0}};
                dtlb_ppn[i] <= {PPN_BITS{1'b0}};
                itlb_r[i] <= 1'b0; itlb_w[i] <= 1'b0; itlb_x[i] <= 1'b0;
                itlb_a[i] <= 1'b0; itlb_d[i] <= 1'b0;
                dtlb_r[i] <= 1'b0; dtlb_w[i] <= 1'b0; dtlb_x[i] <= 1'b0;
                dtlb_a[i] <= 1'b0; dtlb_d[i] <= 1'b0;
            end
        end else begin
            fault_pending <= 1'b0;

            if (satp != satp_last) begin
                satp_last <= satp;
                for (int i = 0; i < TLB_ENTRIES; i = i + 1) begin
                    itlb_valid[i] <= 1'b0;
                    dtlb_valid[i] <= 1'b0;
                end
                state <= S_IDLE;
            end

            case (state)
                S_IDLE: begin
                    if (mmu_en && data_req && !dtlb_hit) begin
                        req_vaddr    <= data_vaddr;
                        req_is_inst  <= 1'b0;
                        req_is_store <= data_write;
                        state        <= S_L1;
                    end else if (mmu_en && inst_req && !itlb_hit) begin
                        req_vaddr    <= inst_vaddr;
                        req_is_inst  <= 1'b1;
                        req_is_store <= 1'b0;
                        state        <= S_L1;
                    end
                end
                S_L1: begin
                    logic pte_v, pte_r, pte_w, pte_x, pte_a, pte_d;
                    logic [PPN_BITS-1:0] pte_ppn;
                    logic pte_leaf;
                    logic pte_ok;
                    logic [PPN_BITS-1:0] ppn_fill;

                    pte_v = ptw_rdata[0];
                    pte_r = ptw_rdata[1];
                    pte_w = ptw_rdata[2];
                    pte_x = ptw_rdata[3];
                    pte_a = ptw_rdata[6];
                    pte_d = ptw_rdata[7];
                    pte_ppn = ptw_rdata[31:10];
                    pte_leaf = pte_r || pte_x;

                    if (!pte_v || (!pte_r && pte_w)) begin
                        fault_pending <= 1'b1;
                        fault_is_inst <= req_is_inst;
                        state <= S_IDLE;
                    end else if (pte_leaf) begin
                        pte_ok = perm_ok(req_is_inst, req_is_store, pte_r, pte_w, pte_x, pte_a, pte_d);
                        if (pte_ok) begin
                            ppn_fill = {pte_ppn[PPN_BITS-1:10], req_vaddr[21:12]};
                            if (req_is_inst) begin
                                itlb_valid[itlb_wr_ptr] <= 1'b1;
                                itlb_vpn[itlb_wr_ptr]   <= req_vaddr[31:12];
                                itlb_ppn[itlb_wr_ptr]   <= ppn_fill;
                                itlb_r[itlb_wr_ptr]     <= pte_r;
                                itlb_w[itlb_wr_ptr]     <= pte_w;
                                itlb_x[itlb_wr_ptr]     <= pte_x;
                                itlb_a[itlb_wr_ptr]     <= pte_a;
                                itlb_d[itlb_wr_ptr]     <= pte_d;
                                itlb_wr_ptr             <= (itlb_wr_ptr + 1) % TLB_ENTRIES;
                            end else begin
                                dtlb_valid[dtlb_wr_ptr] <= 1'b1;
                                dtlb_vpn[dtlb_wr_ptr]   <= req_vaddr[31:12];
                                dtlb_ppn[dtlb_wr_ptr]   <= ppn_fill;
                                dtlb_r[dtlb_wr_ptr]     <= pte_r;
                                dtlb_w[dtlb_wr_ptr]     <= pte_w;
                                dtlb_x[dtlb_wr_ptr]     <= pte_x;
                                dtlb_a[dtlb_wr_ptr]     <= pte_a;
                                dtlb_d[dtlb_wr_ptr]     <= pte_d;
                                dtlb_wr_ptr             <= (dtlb_wr_ptr + 1) % TLB_ENTRIES;
                            end
                        end else begin
                            fault_pending <= 1'b1;
                            fault_is_inst <= req_is_inst;
                        end
                        state <= S_IDLE;
                    end else begin
                        l1_ppn_base <= pte_ppn;
                        state <= S_L0;
                    end
                end
                S_L0: begin
                    logic pte_v, pte_r, pte_w, pte_x, pte_a, pte_d;
                    logic [PPN_BITS-1:0] pte_ppn;
                    logic pte_leaf;
                    logic pte_ok;

                    pte_v = ptw_rdata[0];
                    pte_r = ptw_rdata[1];
                    pte_w = ptw_rdata[2];
                    pte_x = ptw_rdata[3];
                    pte_a = ptw_rdata[6];
                    pte_d = ptw_rdata[7];
                    pte_ppn = ptw_rdata[31:10];
                    pte_leaf = pte_r || pte_x;

                    if (!pte_v || (!pte_r && pte_w) || !pte_leaf) begin
                        fault_pending <= 1'b1;
                        fault_is_inst <= req_is_inst;
                        state <= S_IDLE;
                    end else begin
                        pte_ok = perm_ok(req_is_inst, req_is_store, pte_r, pte_w, pte_x, pte_a, pte_d);
                        if (pte_ok) begin
                            if (req_is_inst) begin
                                itlb_valid[itlb_wr_ptr] <= 1'b1;
                                itlb_vpn[itlb_wr_ptr]   <= req_vaddr[31:12];
                                itlb_ppn[itlb_wr_ptr]   <= pte_ppn;
                                itlb_r[itlb_wr_ptr]     <= pte_r;
                                itlb_w[itlb_wr_ptr]     <= pte_w;
                                itlb_x[itlb_wr_ptr]     <= pte_x;
                                itlb_a[itlb_wr_ptr]     <= pte_a;
                                itlb_d[itlb_wr_ptr]     <= pte_d;
                                itlb_wr_ptr             <= (itlb_wr_ptr + 1) % TLB_ENTRIES;
                            end else begin
                                dtlb_valid[dtlb_wr_ptr] <= 1'b1;
                                dtlb_vpn[dtlb_wr_ptr]   <= req_vaddr[31:12];
                                dtlb_ppn[dtlb_wr_ptr]   <= pte_ppn;
                                dtlb_r[dtlb_wr_ptr]     <= pte_r;
                                dtlb_w[dtlb_wr_ptr]     <= pte_w;
                                dtlb_x[dtlb_wr_ptr]     <= pte_x;
                                dtlb_a[dtlb_wr_ptr]     <= pte_a;
                                dtlb_d[dtlb_wr_ptr]     <= pte_d;
                                dtlb_wr_ptr             <= (dtlb_wr_ptr + 1) % TLB_ENTRIES;
                            end
                        end else begin
                            fault_pending <= 1'b1;
                            fault_is_inst <= req_is_inst;
                        end
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
