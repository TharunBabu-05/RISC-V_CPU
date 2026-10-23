// ============================================================
//  cpu_top_soc.sv  –  RV32I 5-stage CPU — FPGA SoC variant
//
//  Derived from cpu_top.sv (simulation version).
//  Key differences for FPGA synthesis:
//    - External instruction bus (→ BRAM Port A)
//    - External data bus (→ SoC address decoder)
//    - MMU/dcache replaced by simple bus interface
//    - No $readmemh / simulation-only constructs
// ============================================================
`timescale 1ns/1ps

module cpu_top_soc #(
    parameter int XLEN = 32,
    // The FPU is optional on the FPGA (off by default: no firmware uses it).
    parameter bit HAS_FPU = 1'b0,
    parameter bit ENABLE_MMU = 1'b1,
    // Keep code in the dual-port BRAM instruction TCM at full pipeline speed.
    // Fetches outside LOCAL_MEM_BYTES always use the transaction bus.
    parameter bit FAST_LOCAL_IMEM = 1'b1,
    // Local BRAM data uses the synchronous DTCM port. MMIO, translated memory
    // and external memory continue to use the request/response transaction bus.
    parameter bit FAST_LOCAL_DMEM = 1'b1,
    parameter integer LOCAL_MEM_BYTES = 65_536,
    parameter bit ENABLE_ICACHE = 1'b0,
    parameter bit DUAL_ISSUE = 1'b0,
    parameter bit EARLY_FETCH = 1'b1,
    parameter bit STREAM_FETCH = 1'b0
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ext_interrupt,
    input  logic        timer_interrupt,
    input  logic        software_interrupt,

    // ---- One-cycle local instruction-memory port ----
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

`ifdef RISCV_FORMAL
    // The formal wrapper retains the original fixed-latency memory boundary.
    output logic [31:0] dmem_addr,    // Effective address
    output logic [31:0] dmem_wdata,   // Store data
    input  logic [31:0] dmem_rdata,   // Load data
    output logic        dmem_rd_en,   // Load request
    output logic        dmem_wr_en,   // Store request
    output logic [2:0]  dmem_funct3,  // Access width for byte-enables
`else
    // ---- One-cycle local data-memory port ----
    output logic [31:0] dtcm_addr,
    output logic [31:0] dtcm_wdata,
    output logic [3:0]  dtcm_wstrb,
    output logic        dtcm_rd_en,
    output logic        dtcm_wr_en,
    input  logic [31:0] dtcm_rdata,

    // ---- Variable-latency instruction transaction bus ----
    output logic        ibus_req_valid,
    input  logic        ibus_req_ready,
    output logic [31:0] ibus_req_addr,
    output logic        ibus_req_write,
    output logic [3:0]  ibus_req_wstrb,
    output logic [31:0] ibus_req_wdata,
    output logic [1:0]  ibus_req_size,
    input  logic        ibus_rsp_valid,
    output logic        ibus_rsp_ready,
    input  logic [31:0] ibus_rsp_rdata,
    input  logic        ibus_rsp_err,

    // ---- Variable-latency data transaction bus ----
    output logic        dbus_req_valid,
    input  logic        dbus_req_ready,
    output logic [31:0] dbus_req_addr,
    output logic        dbus_req_write,
    output logic [3:0]  dbus_req_wstrb,
    output logic [31:0] dbus_req_wdata,
    output logic [1:0]  dbus_req_size,
    input  logic        dbus_rsp_valid,
    output logic        dbus_rsp_ready,
    input  logic [31:0] dbus_rsp_rdata,
    input  logic        dbus_rsp_err,

    // ---- MMU page-table-walker transaction bus ----
    output logic        ptw_req_valid,
    input  logic        ptw_req_ready,
    output logic [31:0] ptw_req_addr,
    output logic        ptw_req_write,
    output logic [3:0]  ptw_req_wstrb,
    output logic [31:0] ptw_req_wdata,
    output logic [1:0]  ptw_req_size,
    input  logic        ptw_rsp_valid,
    output logic        ptw_rsp_ready,
    input  logic [31:0] ptw_rsp_rdata,
    input  logic        ptw_rsp_err,
`endif

    // ---- Debug / Observation Ports ----
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_alu_result,
    output logic [31:0] dbg_reg_rd_data
`ifdef RISCV_FORMAL
    ,
    // ---- RVFI trace port for riscv-formal (simulation/formal only) ----
    output logic        rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic        rvfi_trap,
    output logic        rvfi_halt,
    output logic        rvfi_intr,
    output logic [1:0]  rvfi_mode,
    output logic [1:0]  rvfi_ixl,
    output logic [4:0]  rvfi_rs1_addr,
    output logic [4:0]  rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [4:0]  rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [3:0]  rvfi_mem_rmask,
    output logic [3:0]  rvfi_mem_wmask,
    output logic [31:0] rvfi_mem_rdata,
    output logic [31:0] rvfi_mem_wdata
`endif
);

    // -------------------------------------------------------
    //  Opcode & opcode constants (used in PC-select logic)
    // -------------------------------------------------------
    // The BRAM bus has no vector load/store path, so the SoC never has a vector unit.
    localparam bit HAS_VEC = 1'b0;

    localparam OP_LUI   = 7'b0110111;
    localparam OP_AUIPC = 7'b0010111;
    localparam OP_JALR  = 7'b1100111;
    localparam OP_SYSTEM = 7'b1110011;
    localparam OP_LOAD_FP  = 7'b0000111;
    localparam OP_STORE_FP = 7'b0100111;
    localparam OP_FP       = 7'b1010011;
    localparam OP_VECTOR   = 7'b1010111;

    localparam [XLEN-1:0]
        EXC_INST_PAGE = {{(XLEN-32){1'b0}}, 32'd12},
        EXC_LOAD_PAGE = {{(XLEN-32){1'b0}}, 32'd13},
        EXC_STORE_PAGE= {{(XLEN-32){1'b0}}, 32'd15};

    // CSR op encoding (matches funct3)
    localparam [2:0]
        CSR_RW  = 3'b001,
        CSR_RS  = 3'b010,
        CSR_RC  = 3'b011,
        CSR_RWI = 3'b101,
        CSR_RSI = 3'b110,
        CSR_RCI = 3'b111;

    // ===================================================
    //  FETCH STAGE
    // ===================================================
    logic [XLEN-1:0] pc, pc_next, pc_plus4;
    logic [31:0] if_instr;
    logic [XLEN-1:0] inst_paddr;
    logic            inst_ready, inst_fault;
    logic            predict_valid, predict_taken;
    logic [XLEN-1:0] predict_target;
    logic fetch_pair;
    logic if_id_pair, id_ex_pair, ex_mem_pair, wb_pair;
    logic [31:0] if_id_second, id_ex_second;
    logic [XLEN-1:0] pair_rs1, pair_rs2, pair_ex_rs1, pair_ex_rs2;
    logic [31:0] pair_result, pair_mem_result, pair_wb_result;
    logic [4:0] pair_mem_rd, pair_wb_rd;
    logic pair_id_stall;

    // PC register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pc <= {XLEN{1'b0}};
        else if (pc_write) pc <= pc_next;
    end

    assign pc_plus4 = pc + {{(XLEN-32){1'b0}}, 32'd4};

`ifdef RISCV_FORMAL
    assign fetch_pair = 1'b0;
    // ---- Formal fixed-latency instruction memory ----
    // To support synchronous BRAM with 1-cycle latency, we drive the
    // address from the COMBINATORIAL next PC. This way, the BRAM latches
    // the address at the same time the PC register updates, and the 
    // instruction is valid during the IF stage.
    // While in reset the PC is held at 0, so the BRAM must read address 0
    // (not pc_next = 4); otherwise the first instruction is skipped.
    assign imem_addr = !rst_n   ? 32'h0 :
                       pc_write ? pc_next[31:0] : pc[31:0];
    assign if_instr  = imem_rdata;
`else
    // Keep the local BRAM address active even in transactional builds. This
    // is the fast ITCM path used by the FPGA SoC; the transaction interface
    // remains available for cache/external-memory configurations.
    assign imem_addr = !rst_n   ? 32'h0 :
                       pc_write ? pc_next[31:0] : pc[31:0];

    // ---- Transactional instruction fetch ----
    // One buffered instruction and one outstanding request are sufficient for
    // correctness with arbitrary memory latency. Redirects invalidate the
    // buffer and tag an outstanding response as stale.
    logic        ifetch_pending;
    logic        ifetch_valid;
    logic        ifetch_request;
    logic        ifetch_killed;
    logic        if_fast_local;
    logic [31:0] ifetch_addr;
    logic        ifetch_bus_error;
    logic [31:0] ifetch_pc;
    logic [31:0] ifetch_data;
    logic        fetch_consumed;
    logic fetch_req_ready, fetch_rsp_valid, fetch_rsp_error, fetch_rsp_pair;
    logic [31:0] fetch_rsp_data, fetch_rsp_second, ifetch_second;
    logic ifetch_pair, pair_eligible;
    wire stream_hit, stream_pair;
    wire [31:0] stream_pc, stream_data, stream_second;
    wire stream_usable = STREAM_FETCH && ENABLE_ICACHE && stream_hit &&
        !ifetch_request && !ifetch_pending && stream_pc == pc &&
        current_priv == 2'b11 && ex_csr_pmpcfg0 == 0 && !ex_csr_satp[31] &&
        pc[31:28] == 4'h8 && pc[1:0] == 0;
    wire fetch_available = ifetch_valid || stream_usable;
    wire [31:0] selected_second = ifetch_valid ? ifetch_second : stream_second;
    wire selected_pair = ifetch_valid ? ifetch_pair : stream_pair;
    wire selected_error = ifetch_valid && ifetch_bus_error;
    wire fetch_request_valid = ifetch_request && rst_n && !flush_if_id;
    wire cache_invalidate = (id_ex_fencei || id_ex_sfence) && ex_redirect;
    wire cacheable_fetch = current_priv == 2'b11 && ex_csr_pmpcfg0 == 0 &&
        !ex_csr_satp[31] && ifetch_addr[31:28] == 4'h8 && ifetch_addr[1:0] == 0;
    // Start the successor lookup as the buffer drains. Restrict this shortcut
    // to unrestricted, untranslated DDR; all other fetches retain validation.
    wire early_fetch = EARLY_FETCH && !STREAM_FETCH && ENABLE_ICACHE && fetch_consumed &&
        !ifetch_bus_error && current_priv == 2'b11 && ex_csr_pmpcfg0 == 0 &&
        !ex_csr_satp[31] && pc[31:28] == 4'h8 &&
        pc_next[31:28] == 4'h8 && pc_next[1:0] == 0;
    // An unpaired aligned fetch still contains a valid second word. Retain
    // it for sequential single issue instead of looking up the same line.
    wire reuse_second = early_fetch && ifetch_pair && !fetch_pair &&
        pc_next == pc_plus4;

    assign if_fast_local = FAST_LOCAL_IMEM && (pc < LOCAL_MEM_BYTES) &&
                           !ex_csr_satp[31];
    // A redirect cannot cancel a request already presented to the arbiter.
    // Hold its address until accepted and drain its response if killed.
    assign ibus_req_write = 1'b0;
    assign ibus_req_wstrb = 4'b0000;
    assign ibus_req_wdata = 32'b0;
    assign ibus_req_size  = 2'd2;
    assign if_instr       = if_fast_local ? imem_rdata : ifetch_valid ? ifetch_data : stream_data;
    assign fetch_consumed = if_id_write && !flush_if_id && !if_fast_local && fetch_available;

    generate if (ENABLE_ICACHE) begin : g_icache
        // Restrict speculative line fills to unpaged, unrestricted machine
        // DDR. Other privilege/PMP/paging configurations keep single fetches.
        rv_icache #(.STREAM(STREAM_FETCH)) u_cache (
            .clk(clk), .rst_n(rst_n),
            .stream_addr(imem_addr), .stream_pc(stream_pc), .stream_data(stream_data),
            .stream_second(stream_second), .stream_hit(stream_hit), .stream_pair(stream_pair),
            .invalidate(cache_invalidate),
            .req_valid(fetch_request_valid), .req_ready(fetch_req_ready),
            .req_addr(ifetch_addr),
            .req_cacheable(cacheable_fetch),
            .rsp_valid(fetch_rsp_valid), .rsp_ready(ifetch_pending),
            .rsp_data(fetch_rsp_data), .rsp_second(fetch_rsp_second),
            .rsp_pair(fetch_rsp_pair), .rsp_err(fetch_rsp_error),
            .mem_req_valid(ibus_req_valid), .mem_req_ready(ibus_req_ready),
            .mem_req_addr(ibus_req_addr), .mem_rsp_valid(ibus_rsp_valid),
            .mem_rsp_ready(ibus_rsp_ready), .mem_rsp_data(ibus_rsp_rdata),
            .mem_rsp_err(ibus_rsp_err)
        );
    end else begin : g_no_icache
        assign stream_hit=0;
        assign stream_pair=0;
        assign stream_pc=0;
        assign stream_data=32'h13;
        assign stream_second=32'h13;
        assign ibus_req_valid = fetch_request_valid;
        assign ibus_req_addr = ifetch_addr;
        assign ibus_rsp_ready = ifetch_pending;
        assign fetch_req_ready = ibus_req_ready;
        assign fetch_rsp_valid = ibus_rsp_valid;
        assign fetch_rsp_data = ibus_rsp_rdata;
        assign fetch_rsp_error = ibus_rsp_err;
        assign fetch_rsp_second = 0;
        assign fetch_rsp_pair = 0;
    end endgenerate
    rv_pair_decode u_pair_decode (.first(if_instr), .second(selected_second),
                                  .eligible(pair_eligible));
    assign fetch_pair = DUAL_ISSUE && ENABLE_ICACHE && !if_fast_local &&
        fetch_available && selected_pair && pair_eligible && !selected_error &&
        !(predict_valid && predict_taken);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifetch_pending       <= 1'b0;
            ifetch_valid         <= 1'b0;
            ifetch_request       <= 1'b0;
            ifetch_killed        <= 1'b0;
            ifetch_addr          <= 32'b0;
            ifetch_bus_error     <= 1'b0;
            ifetch_pc            <= 32'b0;
            ifetch_data          <= 32'h0000_0013;
            ifetch_second        <= 32'h0000_0013;
            ifetch_pair          <= 0;
        end else begin
            if (flush_if_id) begin
                ifetch_valid     <= 1'b0;
                ifetch_bus_error <= 1'b0;
                ifetch_killed    <= 1'b1;
                if (!ifetch_pending)
                    ifetch_request <= 1'b0;
            end else if (fetch_consumed) begin
                ifetch_valid     <= reuse_second;
                ifetch_bus_error <= 1'b0;
                if (reuse_second) begin
                    ifetch_data <= ifetch_second;
                    ifetch_pc <= pc_next[31:0];
                    ifetch_pair <= 1'b0;
                end
            end

            if (!if_fast_local && rst_n && inst_ready && !inst_fault &&
                !ifetch_request && !ifetch_pending && !reuse_second &&
                (!fetch_available || early_fetch) && !flush_if_id) begin
                ifetch_request <= 1'b1;
                ifetch_killed  <= 1'b0;
                ifetch_addr    <= early_fetch ? pc_next[31:0] : inst_paddr[31:0];
                ifetch_pc      <= early_fetch ? pc_next[31:0] : pc[31:0];
            end

            if (fetch_request_valid && fetch_req_ready) begin
                ifetch_request <= 1'b0;
                ifetch_pending <= 1'b1;
            end

            if (fetch_rsp_valid && ifetch_pending) begin
                ifetch_pending <= 1'b0;
                if (!flush_if_id && !ifetch_killed) begin
                    ifetch_valid     <= 1'b1;
                    ifetch_data      <= fetch_rsp_error ? 32'h0000_0013 : fetch_rsp_data;
                    ifetch_bus_error <= fetch_rsp_error;
                    ifetch_second    <= fetch_rsp_second;
                    ifetch_pair      <= fetch_rsp_pair;
                end
            end
        end
    end
`endif

    branch_predictor #(.XLEN(XLEN)) u_bpred (
        .clk           (clk),
        .rst_n         (rst_n),
        .pc_fetch      (pc),
        .predict_valid (predict_valid),
        .predict_taken (predict_taken),
        .predict_target(predict_target),
        .update        ((id_ex_branch || id_ex_jump) && !muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall),
        .pc_update     (id_ex_pc),
        .actual_taken  (branch_taken || id_ex_jump),
        .actual_target ((id_ex_jump && id_ex_opcode == OP_JALR) ? ex_jalr_target : ex_branch_target)
    );

    // ===================================================
    //  IF / ID  pipeline register
    // ===================================================
    logic [XLEN-1:0] if_id_pc;
    logic [XLEN-1:0] if_id_pred_target;
    logic [31:0] if_id_instr;
    logic        if_id_pred_taken;
    logic        if_id_valid;   // 0 for reset/flush bubbles
    logic        if_id_bus_error;
    logic        decode_accept;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pair <= 0;
            if_id_second <= 32'h13;
        end else if (if_id_write) begin
            if_id_pair <= !flush_if_id && fetch_pair;
`ifndef RISCV_FORMAL
            if_id_second <= selected_second;
`endif
        end else if (decode_accept) if_id_pair <= 0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= {XLEN{1'b0}};
            if_id_pred_target <= {XLEN{1'b0}};
            if_id_pred_taken  <= 1'b0;
            if_id_instr <= 32'h0000_0013; // NOP
            if_id_valid <= 1'b0;
            if_id_bus_error <= 1'b0;
        end else if (if_id_write) begin
            if (flush_if_id) begin
                if_id_pc    <= {XLEN{1'b0}};
                if_id_pred_target <= {XLEN{1'b0}};
                if_id_pred_taken  <= 1'b0;
                if_id_instr <= 32'h0000_0013;
                if_id_valid <= 1'b0;
                if_id_bus_error <= 1'b0;
            end else begin
`ifdef RISCV_FORMAL
                if_id_pc    <= pc;
                if_id_bus_error <= 1'b0;
`else
                if_id_pc    <= if_fast_local || !ifetch_valid ? pc : ifetch_pc;
                if_id_bus_error <= !if_fast_local && selected_error;
`endif
                if_id_pred_target <= predict_target;
                if_id_pred_taken  <= predict_valid && predict_taken;
                if_id_instr <= if_instr;
                if_id_valid <= 1'b1;
            end
        end else if (decode_accept) begin
            // A variable-latency frontend can leave IF/ID unchanged for many
            // cycles. Retire its valid token after ID/EX accepts it so the
            // same instruction cannot execute again while the next fetch is
            // still outstanding.
            if_id_valid     <= 1'b0;
            if_id_bus_error <= 1'b0;
        end
    end

    // ===================================================
    //  DECODE STAGE
    // ===================================================
    // Register file reads
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [XLEN-1:0] id_rs1_data, id_rs2_data;
    logic [XLEN-1:0] id_imm;
    logic [31:0] id_fp_rs1_data, id_fp_rs2_data, id_fp_rs3_data, fp_wb_data;
    logic [127:0] id_vec_rs1_data, id_vec_rs2_data, id_vec_vd_data, id_vec_v0_data, vec_wb_data;
    logic [4:0] fp_wb_rd, vec_wb_rd;
    logic fp_wb_write, vec_wb_write;

    assign id_rs1_addr = if_id_instr[19:15];
    assign id_rs2_addr = if_id_instr[24:20];
    assign id_rd_addr  = if_id_instr[11:7];

    // Writeback data (from WB stage, fed to regfile)
    logic [XLEN-1:0] wb_wr_data;
    logic [4:0]  wb_rd_addr;
    logic        wb_reg_write;

    regfile #(.XLEN(XLEN), .SECOND_PORT(DUAL_ISSUE)) u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs1_data (id_rs1_data),
        .rs2_addr (id_rs2_addr),
        .rs2_data (id_rs2_data),
        .rd_addr  (wb_rd_addr),
        .rd_data  (wb_wr_data),
        .reg_write(wb_reg_write),
        .rs1_second(if_id_second[19:15]), .rs2_second(if_id_second[24:20]),
        .rs1_second_data(pair_rs1), .rs2_second_data(pair_rs2),
        .rd_second(pair_wb_rd), .data_second(pair_wb_result),
        .write_second(wb_pair)
    );

    generate
        if (HAS_FPU) begin : g_fp_regs
            fp_regfile #(.FLEN(32)) u_fp_regfile (
                .clk      (clk),
                .rst_n    (rst_n),
                .rs1_addr (id_rs1_addr),
                .rs1_data (id_fp_rs1_data),
                .rs2_addr (id_rs2_addr),
                .rs2_data (id_fp_rs2_data),
                .rs3_addr (if_id_instr[31:27]),
                .rs3_data (id_fp_rs3_data),
                .rd_addr  (fp_wb_rd),
                .rd_data  (fp_wb_data),
                .reg_write(fp_wb_write)
            );
        end else begin : g_no_fp_regs
            assign id_fp_rs1_data = 32'b0;
            assign id_fp_rs2_data = 32'b0;
            assign id_fp_rs3_data = 32'b0;
        end

        if (HAS_VEC) begin : g_vec_regs
            vector_regfile #(.VLEN(128)) u_vec_regfile (
                .clk      (clk),
                .rst_n    (rst_n),
                .rs1_addr (id_rs1_addr),
                .rs1_data (id_vec_rs1_data),
                .rs2_addr (id_rs2_addr),
                .rs2_data (id_vec_rs2_data),
                .rd_raddr (id_rd_addr),
                .rd_rdata (id_vec_vd_data),
                .v0_data  (id_vec_v0_data),
                .rd_addr  (vec_wb_rd),
                .rd_data  (vec_wb_data),
                .reg_write(vec_wb_write)
            );
        end else begin : g_no_vec_regs
            assign id_vec_rs1_data = 128'b0;
            assign id_vec_rs2_data = 128'b0;
            assign id_vec_vd_data  = 128'b0;
            assign id_vec_v0_data  = 128'b0;
        end
    endgenerate

    imm_gen #(.XLEN(XLEN)) u_immgen (
        .instr  (if_id_instr),
        .imm_out(id_imm)
    );

    // CSR fields (Zicsr)
    logic [11:0] id_csr_addr;
    logic [XLEN-1:0] id_csr_zimm;
    logic        id_csr_imm;
    assign id_csr_addr = if_id_instr[31:20];
    assign id_csr_zimm = {{(XLEN-5){1'b0}}, if_id_instr[19:15]};
    assign id_csr_imm  = id_csr_op[2];

    // Control signals
    logic        id_reg_write, id_alu_src, id_mem_read, id_mem_write;
    logic        id_mem_to_reg, id_branch, id_jump;
    logic        id_fp_en, id_fp_load, id_fp_store, id_fp_reg_write;
    logic        id_vec_en, id_vec_reg_write;
    logic        id_csr_en, id_ecall, id_ebreak, id_mret, id_sret, id_sfence;
    logic [2:0]  id_csr_op;
    logic [1:0]  id_alu_op;
    logic [3:0]  id_alu_ctrl;
    logic        id_muldiv_en;
    logic [2:0]  id_muldiv_op;

    control_unit u_ctrl (
        .opcode    (if_id_instr[6:0]),
        .funct3    (if_id_instr[14:12]),
        .funct7    (if_id_instr[31:25]),
        .rs2_imm   (if_id_instr[24:20]),
        .reg_write (id_reg_write),
        .alu_src   (id_alu_src),
        .mem_read  (id_mem_read),
        .mem_write (id_mem_write),
        .mem_to_reg(id_mem_to_reg),
        .branch    (id_branch),
        .jump      (id_jump),
        .csr_en    (id_csr_en),
        .csr_op    (id_csr_op),
        .ecall     (id_ecall),
        .ebreak    (id_ebreak),
        .alu_op    (id_alu_op),
        .alu_ctrl  (id_alu_ctrl),
        .muldiv_en (id_muldiv_en),
        .muldiv_op (id_muldiv_op)
    );

    // F / V decode (see ext_decode in control_unit.sv)
    logic       id_ext_is, id_ext_illegal, id_f_any, id_f_uses_rm, id_f_wr_int;
    logic       id_f_src1, id_f_src2, id_f_src3;
    logic [4:0] id_f_op;
    logic       id_v_any, id_v_cfg, id_v_load, id_v_store, id_v_wr_int;
    logic       id_v_src1, id_v_src2, id_v_srcd, id_v_src0;
    logic [1:0] id_v_eew;

    ext_decode #(.HAS_FPU(HAS_FPU), .HAS_VEC(HAS_VEC)) u_ext_id (
        .instr    (if_id_instr),
        .is_ext   (id_ext_is),
        .illegal  (id_ext_illegal),
        .f_any    (id_f_any),
        .f_op_en  (id_fp_en),
        .f_op     (id_f_op),
        .f_uses_rm(id_f_uses_rm),
        .f_load   (id_fp_load),
        .f_store  (id_fp_store),
        .f_wr_fp  (id_fp_reg_write),
        .f_wr_int (id_f_wr_int),
        .f_src1   (id_f_src1),
        .f_src2   (id_f_src2),
        .f_src3   (id_f_src3),
        .v_any    (id_v_any),
        .v_cfg    (id_v_cfg),
        .v_arith  (id_vec_en),
        .v_load   (id_v_load),
        .v_store  (id_v_store),
        .v_eew    (id_v_eew),
        .v_wr_vec (id_vec_reg_write),
        .v_wr_int (id_v_wr_int),
        .v_src1   (id_v_src1),
        .v_src2   (id_v_src2),
        .v_srcd   (id_v_srcd),
        .v_src0   (id_v_src0)
    );

    assign id_sfence = (if_id_instr[6:0] == OP_SYSTEM) &&
                       (if_id_instr[14:12] == 3'b000) &&
                       (if_id_instr[31:25] == 7'b0001001);

    // Illegal-instruction detection (encodings this core does not implement)
    logic id_illegal, id_illegal_base, id_ok, id_fencei;
    illegal_detect #(.XLEN(XLEN)) u_illegal (
        .instr  (if_id_instr),
        .illegal(id_illegal_base)
    );
    assign id_illegal = id_ext_is ? id_ext_illegal : id_illegal_base;
    assign id_ok     = !id_illegal;
    assign id_fencei = (if_id_instr[6:0] == 7'b0001111) && (if_id_instr[14:12] == 3'b001);

    // Hazard unit
    logic pc_write, if_id_write, control_mux;
    (* keep *) logic hazard_pc_write, hazard_if_id_write, hazard_control_mux;
    logic muldiv_stall, fpu_stall, vec_stall, mem_stall, mmu_stall;
    logic flush_if_id;  // from branch taken (driven below)

    logic [4:0] hazard_rs1, hazard_rs2;
    assign hazard_rs1 = id_csr_imm ? 5'b0 : id_rs1_addr;
    assign hazard_rs2 = id_csr_en  ? 5'b0 : id_rs2_addr;

    hazard_unit u_hazard (
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_rd      (id_ex_rd),
        .if_id_rs1     (hazard_rs1),
        .if_id_rs2     (hazard_rs2),
        .pc_write      (hazard_pc_write),
        .if_id_write   (hazard_if_id_write),
        .control_mux   (hazard_control_mux)
    );

    // FP and vector results reach later instructions only through the
    // register-file write-through bypass, so a reader waits in ID while the
    // producer is still in EX or MEM.
    logic fp_pend_rs1, fp_pend_rs2, fp_pend_rs3, vec_pend_rs1, vec_pend_rs2, vec_pend_rd, vec_pend_v0;
    logic ext_stall, id_stall, frontend_ready;
    assign fp_pend_rs1  = (id_ex_fp_reg_write  && id_ex_rd == id_rs1_addr) || (ex_mem_fp_reg_write  && ex_mem_rd == id_rs1_addr);
    assign fp_pend_rs2  = (id_ex_fp_reg_write  && id_ex_rd == id_rs2_addr) || (ex_mem_fp_reg_write  && ex_mem_rd == id_rs2_addr);
    assign fp_pend_rs3  = (id_ex_fp_reg_write  && id_ex_rd == if_id_instr[31:27]) ||
                          (ex_mem_fp_reg_write && ex_mem_rd == if_id_instr[31:27]);
    assign vec_pend_rs1 = (id_ex_vec_reg_write && id_ex_rd == id_rs1_addr) || (ex_mem_vec_reg_write && ex_mem_rd == id_rs1_addr);
    assign vec_pend_rs2 = (id_ex_vec_reg_write && id_ex_rd == id_rs2_addr) || (ex_mem_vec_reg_write && ex_mem_rd == id_rs2_addr);
    assign vec_pend_rd  = (id_ex_vec_reg_write && id_ex_rd == id_rd_addr)  || (ex_mem_vec_reg_write && ex_mem_rd == id_rd_addr);
    assign vec_pend_v0  = (id_ex_vec_reg_write && id_ex_rd == 5'd0)        || (ex_mem_vec_reg_write && ex_mem_rd == 5'd0);
    assign ext_stall = if_id_valid && (
                           (id_f_src1 && fp_pend_rs1) || (id_f_src2 && fp_pend_rs2) || (id_f_src3 && fp_pend_rs3) ||
                           (id_v_src1 && vec_pend_rs1) || (id_v_src2 && vec_pend_rs2) ||
                           (id_v_srcd && vec_pend_rd)  || (id_v_src0 && vec_pend_v0));
    assign id_stall = hazard_control_mux || ext_stall || pair_id_stall;

    // Lane 1 uses register-file operands. Interlock until older producers
    // reach WB; the write-first bypass then supplies their final values.
    function automatic pair_reads(input [31:0] insn, input [4:0] rd);
        pair_reads = rd != 0 &&
            (((insn[6:0] == 7'h13 || insn[6:0] == 7'h33) && insn[19:15] == rd) ||
             (insn[6:0] == 7'h33 && insn[24:20] == rd));
    endfunction
    assign pair_id_stall = DUAL_ISSUE && if_id_valid && (
        (id_ex_pair && id_ex_second[11:7] != 0 &&
            (hazard_rs1 == id_ex_second[11:7] || hazard_rs2 == id_ex_second[11:7])) ||
        (ex_mem_pair && pair_mem_rd != 0 &&
            (hazard_rs1 == pair_mem_rd || hazard_rs2 == pair_mem_rd)) ||
        (if_id_pair && (
            (id_ex_valid && id_ex_reg_write && pair_reads(if_id_second, id_ex_rd)) ||
            (ex_mem_valid && ex_mem_reg_write && pair_reads(if_id_second, ex_mem_rd)) ||
            (id_ex_pair && pair_reads(if_id_second, id_ex_second[11:7])) ||
            (ex_mem_pair && pair_reads(if_id_second, pair_mem_rd)))));

`ifdef RISCV_FORMAL
    assign frontend_ready = 1'b1;
`else
    assign frontend_ready = if_fast_local ? 1'b1 : fetch_available;
`endif
    // A redirect is allowed to update the PC immediately. Normal sequential
    // progress consumes exactly one buffered transaction response.
    assign pc_write    = (flush_ex || ((!id_stall) && frontend_ready)) &&
                         !muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall;
    assign if_id_write = (flush_ex || ((!id_stall) && frontend_ready)) &&
                         !muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall;
    assign control_mux = id_stall;

    // ===================================================
    //  ID / EX  pipeline register
    // ===================================================
    logic [XLEN-1:0] id_ex_pc, id_ex_rs1, id_ex_rs2, id_ex_imm, id_ex_pred_target;
    logic [31:0] id_ex_fp_rs1, id_ex_fp_rs2, id_ex_fp_rs3;
    logic [127:0] id_ex_vec_rs1, id_ex_vec_rs2, id_ex_vec_vd, id_ex_vec_v0;
    logic [4:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd;
    logic [2:0]  id_ex_funct3;
    logic        id_ex_reg_write, id_ex_alu_src, id_ex_mem_read;
    logic        id_ex_mem_write, id_ex_mem_to_reg, id_ex_branch, id_ex_jump;
    logic        id_ex_fp_en, id_ex_fp_load, id_ex_fp_store, id_ex_fp_reg_write;
    logic        id_ex_vec_en, id_ex_vec_reg_write;
    logic        id_ex_csr_en, id_ex_ecall_r, id_ex_ebreak_r, id_ex_mret_r;
    logic        id_ex_sret_r;
    logic        id_ex_sfence;
    logic [2:0]  id_ex_csr_op;
    logic [11:0] id_ex_csr_addr;
    logic [XLEN-1:0] id_ex_csr_zimm;
    logic [3:0]  id_ex_alu_ctrl;
    logic [6:0]  id_ex_opcode;
    logic        id_ex_muldiv_en, id_ex_pred_taken;
    logic [2:0]  id_ex_muldiv_op;
    logic        id_ex_write;
    logic        id_ex_valid, id_ex_illegal, id_ex_fencei, id_ex_bus_error;
    logic [31:0] id_ex_instr;

    assign id_mret = (if_id_instr == 32'h3020_0073);
    assign id_sret = (if_id_instr == 32'h1020_0073);

    assign id_ex_write = ~muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall;
    assign decode_accept = id_ex_write && !control_mux && if_id_valid;

    rv_pair_alu u_pair_alu (.instr(id_ex_second), .pc(id_ex_pc[31:0] + 32'd4),
        .rs1(pair_ex_rs1[31:0]), .rs2(pair_ex_rs2[31:0]), .result(pair_result));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pair <= 0;
            id_ex_second <= 32'h13;
            pair_ex_rs1 <= 0;
            pair_ex_rs2 <= 0;
        end else if ((flush_ex && !mem_stall && !mmu_stall) ||
                     (control_mux && id_ex_write) || (id_ex_write && !if_id_valid))
            id_ex_pair <= 0;
        else if (id_ex_write) begin
            id_ex_pair <= if_id_pair && DUAL_ISSUE;
            id_ex_second <= if_id_second;
            pair_ex_rs1 <= pair_rs1;
            pair_ex_rs2 <= pair_rs2;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_pair <= 0;
            pair_mem_rd <= 0;
            pair_mem_result <= 0;
            wb_pair <= 0;
            pair_wb_rd <= 0;
            pair_wb_result <= 0;
        end else begin
            if (!mem_stall && !mmu_stall) begin
                ex_mem_pair <= id_ex_pair && !muldiv_stall && !fpu_stall &&
                    !vec_stall && !ex_exc_taken && !flush_ex_mem &&
                    !pmp_access_fault && !page_fault_exception;
                pair_mem_rd <= id_ex_second[11:7];
                pair_mem_result <= pair_result;
            end
            wb_pair <= ex_mem_pair && !mem_stall && !mmu_stall &&
                !bus_data_fault && !mem_page_fault;
            pair_wb_rd <= pair_mem_rd;
            pair_wb_result <= pair_mem_result;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pc         <= {XLEN{1'b0}};
            id_ex_pred_target<= {XLEN{1'b0}};
            id_ex_rs1        <= {XLEN{1'b0}};
            id_ex_rs2        <= {XLEN{1'b0}};
            id_ex_fp_rs1     <= 32'b0;
            id_ex_fp_rs2     <= 32'b0;
            id_ex_fp_rs3     <= 32'b0;
            id_ex_vec_rs1    <= 128'b0;
            id_ex_vec_rs2    <= 128'b0;
            id_ex_vec_vd     <= 128'b0;
            id_ex_vec_v0     <= 128'b0;
            id_ex_imm        <= {XLEN{1'b0}};
            id_ex_rs1_addr   <= 5'b0;
            id_ex_rs2_addr   <= 5'b0;
            id_ex_rd         <= 5'b0;
            id_ex_funct3     <= 3'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_alu_src    <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
            id_ex_csr_en     <= 1'b0;
            id_ex_ecall_r    <= 1'b0;
            id_ex_ebreak_r   <= 1'b0;
            id_ex_mret_r     <= 1'b0;
            id_ex_sret_r     <= 1'b0;
            id_ex_sfence     <= 1'b0;
            id_ex_csr_op     <= 3'b0;
            id_ex_csr_addr   <= 12'b0;
            id_ex_csr_zimm   <= {XLEN{1'b0}};
            id_ex_alu_ctrl   <= 4'b0;
            id_ex_opcode     <= 7'b0;
            id_ex_muldiv_en  <= 1'b0;
            id_ex_pred_taken <= 1'b0;
            id_ex_fp_en      <= 1'b0;
            id_ex_fp_load    <= 1'b0;
            id_ex_fp_store   <= 1'b0;
            id_ex_fp_reg_write <= 1'b0;
            id_ex_vec_en     <= 1'b0;
            id_ex_vec_reg_write <= 1'b0;
            id_ex_muldiv_op  <= 3'b0;
            id_ex_valid      <= 1'b0;
            id_ex_illegal    <= 1'b0;
            id_ex_fencei     <= 1'b0;
            id_ex_bus_error  <= 1'b0;
            id_ex_instr      <= 32'h0000_0013;
        // Bubble on a redirect, or on an ID stall while EX advances. A stall in
        // ID must never overwrite an instruction still busy in EX (mul/div,
        // FPU, vector unit) or held by a frozen MEM stage.
        end else if ((flush_ex && !mem_stall && !mmu_stall) ||
                     (control_mux && id_ex_write) ||
                     (id_ex_write && !if_id_valid)) begin
            id_ex_pc         <= {XLEN{1'b0}};
            id_ex_pred_target<= {XLEN{1'b0}};
            id_ex_rs1        <= {XLEN{1'b0}};
            id_ex_rs2        <= {XLEN{1'b0}};
            id_ex_fp_rs1     <= 32'b0;
            id_ex_fp_rs2     <= 32'b0;
            id_ex_fp_rs3     <= 32'b0;
            id_ex_vec_rs1    <= 128'b0;
            id_ex_vec_rs2    <= 128'b0;
            id_ex_vec_vd     <= 128'b0;
            id_ex_vec_v0     <= 128'b0;
            id_ex_imm        <= {XLEN{1'b0}};
            id_ex_rs1_addr   <= 5'b0;
            id_ex_rs2_addr   <= 5'b0;
            id_ex_rd         <= 5'b0;
            id_ex_funct3     <= 3'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_alu_src    <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
            id_ex_csr_en     <= 1'b0;
            id_ex_ecall_r    <= 1'b0;
            id_ex_ebreak_r   <= 1'b0;
            id_ex_mret_r     <= 1'b0;
            id_ex_sret_r     <= 1'b0;
            id_ex_sfence     <= 1'b0;
            id_ex_csr_op     <= 3'b0;
            id_ex_csr_addr   <= 12'b0;
            id_ex_csr_zimm   <= {XLEN{1'b0}};
            id_ex_alu_ctrl   <= 4'b0;
            id_ex_opcode     <= 7'b0;
            id_ex_muldiv_en  <= 1'b0;
            id_ex_pred_taken <= 1'b0;
            id_ex_fp_en      <= 1'b0;
            id_ex_fp_load    <= 1'b0;
            id_ex_fp_store   <= 1'b0;
            id_ex_fp_reg_write <= 1'b0;
            id_ex_vec_en     <= 1'b0;
            id_ex_vec_reg_write <= 1'b0;
            id_ex_muldiv_op  <= 3'b0;
            id_ex_valid      <= 1'b0;
            id_ex_illegal    <= 1'b0;
            id_ex_fencei     <= 1'b0;
            id_ex_bus_error  <= 1'b0;
            id_ex_instr      <= 32'h0000_0013;
        end else if (id_ex_write) begin
            id_ex_pc         <= if_id_pc;
            id_ex_pred_target<= if_id_pred_target;
            id_ex_rs1        <= id_rs1_data;
            id_ex_rs2        <= id_rs2_data;
            id_ex_fp_rs1     <= id_fp_rs1_data;
            id_ex_fp_rs2     <= id_fp_rs2_data;
            id_ex_fp_rs3     <= id_fp_rs3_data;
            id_ex_vec_rs1    <= id_vec_rs1_data;
            id_ex_vec_rs2    <= id_vec_rs2_data;
            id_ex_vec_vd     <= id_vec_vd_data;
            id_ex_vec_v0     <= id_vec_v0_data;
            id_ex_imm        <= id_imm;
            id_ex_rs1_addr   <= id_rs1_addr;
            id_ex_rs2_addr   <= id_rs2_addr;
            id_ex_rd         <= id_rd_addr;
            id_ex_funct3     <= if_id_instr[14:12];
            id_ex_reg_write  <= (id_reg_write || id_f_wr_int || id_v_wr_int) && id_ok;
            id_ex_alu_src    <= id_alu_src || id_fp_load || id_fp_store;   // FLW/FSW: rs1 + imm
            id_ex_mem_read   <= (id_mem_read || id_fp_load) && id_ok;
            id_ex_mem_write  <= (id_mem_write || id_fp_store) && id_ok;
            id_ex_mem_to_reg <= (id_mem_to_reg || id_fp_load) && id_ok;
            id_ex_branch     <= (id_branch) && id_ok;
            id_ex_jump       <= (id_jump) && id_ok;
            id_ex_csr_en     <= (id_csr_en) && id_ok;
            id_ex_ecall_r    <= (id_ecall) && id_ok;
            id_ex_ebreak_r   <= (id_ebreak) && id_ok;
            id_ex_mret_r     <= (id_mret) && id_ok;
            id_ex_sret_r     <= (id_sret) && id_ok;
            id_ex_sfence     <= (id_sfence) && id_ok;
            id_ex_csr_op     <= id_csr_op;
            id_ex_csr_addr   <= id_csr_addr;
            id_ex_csr_zimm   <= id_csr_zimm;
            id_ex_alu_ctrl   <= id_alu_ctrl;
            id_ex_opcode     <= if_id_instr[6:0];
            id_ex_muldiv_en  <= (id_muldiv_en) && id_ok;
            id_ex_pred_taken <= if_id_pred_taken;
            id_ex_fp_en      <= (id_fp_en) && id_ok;
            id_ex_fp_load    <= (id_fp_load) && id_ok;
            id_ex_fp_store   <= (id_fp_store) && id_ok;
            id_ex_fp_reg_write <= (id_fp_reg_write) && id_ok;
            id_ex_vec_en     <= (id_vec_en) && id_ok;
            id_ex_vec_reg_write <= (id_vec_reg_write) && id_ok;
            id_ex_muldiv_op  <= id_muldiv_op;
            id_ex_valid      <= if_id_valid;
            id_ex_illegal    <= id_illegal && if_id_valid;
            id_ex_fencei     <= id_fencei && id_ok;
            id_ex_bus_error  <= if_id_bus_error && if_id_valid;
            id_ex_instr      <= if_id_instr;
        end else begin
            // EX is held: capture the forwarded operands so they stay valid
            // after their producer leaves the pipeline
            id_ex_rs1        <= ex_fwd_a;
            id_ex_rs2        <= ex_fwd_b;
        end
    end

    // ===================================================
    //  EXECUTE STAGE
    // ===================================================
    // Forwarding
    logic [1:0] fwd_a, fwd_b;

    forwarding_unit u_fwd (
        .ex_rs1          (id_ex_rs1_addr),
        .ex_rs2          (id_ex_rs2_addr),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd       (wb_rd_addr),
        .mem_wb_reg_write(wb_reg_write),
        .fwd_a           (fwd_a),
        .fwd_b           (fwd_b)
    );

    logic [XLEN-1:0] ex_fwd_a, ex_fwd_b, ex_alu_b, ex_alu_result_raw, ex_result;
    logic        ex_zero;

    // Value forwarded from EX/MEM: what that instruction will write back.
    // CSR reads and JAL/JALR links are not in ex_mem_alu_result.
    logic [XLEN-1:0] ex_mem_fwd_data;

    // Forwarding MUXes
    always_comb begin
        case (fwd_a)
            2'b10:   ex_fwd_a = ex_mem_fwd_data;     // EX/MEM forward
            2'b01:   ex_fwd_a = wb_wr_data;           // MEM/WB forward
            default: ex_fwd_a = id_ex_rs1;
        endcase

        case (fwd_b)
            2'b10:   ex_fwd_b = ex_mem_fwd_data;
            2'b01:   ex_fwd_b = wb_wr_data;
            default: ex_fwd_b = id_ex_rs2;
        endcase
    end

    // ALU source MUX (imm or register)
    assign ex_alu_b = id_ex_alu_src ? id_ex_imm : ex_fwd_b;

    // Special case: LUI passes immediate directly, AUIPC adds PC+imm
    logic [XLEN-1:0] ex_alu_a;
    always_comb begin
        if (id_ex_opcode == OP_AUIPC)
            ex_alu_a = id_ex_pc;
        else if (id_ex_opcode == OP_LUI)
            ex_alu_a = {XLEN{1'b0}};
        else
            ex_alu_a = ex_fwd_a;
    end

    alu #(.XLEN(XLEN)) u_alu (
        .a       (ex_alu_a),
        .b       (ex_alu_b),
        .alu_ctrl(id_ex_alu_ctrl),
        .result  (ex_alu_result_raw),
        .zero    (ex_zero)
    );

    // M extension (mul/div) unit
    logic        muldiv_start, muldiv_done, muldiv_busy;
    logic [XLEN-1:0] muldiv_result;

    assign muldiv_start = id_ex_muldiv_en && !muldiv_busy && !flush_ex;

    muldiv_unit #(.XLEN(XLEN)) u_muldiv (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (flush_ex),
        .start (muldiv_start),
        .op    (id_ex_muldiv_op),
        .a     (ex_fwd_a),
        .b     (ex_fwd_b),
        .busy  (muldiv_busy),
        .done  (muldiv_done),
        .result(muldiv_result)
    );

    assign muldiv_stall = id_ex_muldiv_en && !muldiv_done;
    assign ex_result = id_ex_muldiv_en ? muldiv_result :
                       ex_f_wr_int     ? {{(XLEN-32){fpu_result[31]}}, fpu_result} :
                       ex_v_cfg        ? ex_vcfg_vl :
                       ex_v_wr_int     ? {{(XLEN-32){vec_scalar_out[31]}}, vec_scalar_out} :
                                         ex_alu_result_raw;

    // Re-decode the F / V instruction in EX for its operation details
    logic       ex_f_any, ex_f_uses_rm, ex_f_wr_int, ex_v_cfg, ex_v_arith, ex_v_load, ex_v_store, ex_v_wr_int;
    logic [4:0] ex_f_op;
    logic [1:0] ex_v_eew;
    ext_decode #(.HAS_FPU(HAS_FPU), .HAS_VEC(HAS_VEC)) u_ext_ex (
        .instr(id_ex_instr), .is_ext(), .illegal(),
        .f_any(ex_f_any), .f_op_en(), .f_op(ex_f_op), .f_uses_rm(ex_f_uses_rm), .f_load(), .f_store(),
        .f_wr_fp(), .f_wr_int(ex_f_wr_int), .f_src1(), .f_src2(), .f_src3(),
        .v_any(), .v_cfg(ex_v_cfg), .v_arith(ex_v_arith), .v_load(ex_v_load), .v_store(ex_v_store), .v_eew(ex_v_eew),
        .v_wr_vec(), .v_wr_int(ex_v_wr_int), .v_src1(), .v_src2(), .v_srcd(), .v_src0()
    );

    // F: dynamic rounding mode and mstatus.FS gating
    logic [2:0]      ex_frm, ex_f_rm;
    logic            ex_f_illegal;
    logic [XLEN-1:0] ex_vl, ex_vtype, ex_vstart;
    assign ex_f_rm      = (id_ex_instr[14:12] == 3'b111) ? ex_frm : id_ex_instr[14:12];
    assign ex_f_illegal = ex_f_any && ((ex_csr_mstatus[14:13] == 2'b00) || (ex_f_uses_rm && ex_f_rm > 3'd4));

    logic fpu_start, fpu_done, fpu_busy;
    logic [31:0] fpu_result;
    logic [4:0]  fpu_flags;
    assign fpu_start = id_ex_fp_en && !fpu_busy && !flush_ex && !ex_f_illegal;

    generate
        if (HAS_FPU) begin : g_fpu
            fpu_unit #(.FLEN(32)) u_fpu (
                .clk   (clk),
                .rst_n (rst_n),
                .clear (flush_ex),
                .start (fpu_start),
                .op    (ex_f_op),
                .rm    (ex_f_rm),
                .a     (id_ex_fp_rs1),
                .b     (id_ex_fp_rs2),
                .c     (id_ex_fp_rs3),
                .x     (ex_fwd_a[31:0]),
                .busy  (fpu_busy),
                .done  (fpu_done),
                .result(fpu_result),
                .flags (fpu_flags)
            );
        end else begin : g_no_fpu
            assign fpu_busy = 1'b0;
            assign fpu_done = 1'b0;
            assign fpu_result = 32'b0;
            assign fpu_flags = 5'b0;
        end
    endgenerate

    assign fpu_stall = id_ex_fp_en && !fpu_done && !ex_f_illegal;

    // V: vtype checks (vill, vstart = 0, EEW = SEW for loads/stores)
    logic [2:0] ex_sew;
    logic       ex_v_illegal, ex_v_mis;
    assign ex_sew       = ex_vtype[5:3];
    assign ex_v_illegal = (ex_v_arith || ex_v_load || ex_v_store) &&
                          (ex_vtype[XLEN-1] || (ex_vstart != {XLEN{1'b0}}) ||
                           ((ex_v_load || ex_v_store) && ({1'b0, ex_v_eew} != ex_sew)));
    assign ex_v_mis     = (ex_v_eew == 2'd1) ? ex_fwd_a[0] : (ex_v_eew == 2'd2) ? |ex_fwd_a[1:0] : 1'b0;

    logic vec_start, vec_done, vec_busy;
    logic [127:0] vec_result;
    logic [31:0]  vec_scalar_out;
    assign vec_start = id_ex_vec_en && !vec_busy && !flush_ex && !ex_v_illegal;

    generate
        if (HAS_VEC) begin : g_vec
            vector_unit #(.VLEN(128)) u_vec (
                .clk       (clk),
                .rst_n     (rst_n),
                .clear     (flush_ex),
                .start     (vec_start),
                .instr     (id_ex_instr),
                .vs1       (id_ex_vec_rs1),
                .vs2       (id_ex_vec_rs2),
                .vd_old    (id_ex_vec_vd),
                .v0        (id_ex_vec_v0),
                .scalar    (ex_fwd_a[31:0]),
                .sew       (ex_sew),
                .vl        (ex_vl[31:0]),
                .busy      (vec_busy),
                .done      (vec_done),
                .result    (vec_result),
                .scalar_out(vec_scalar_out)
            );
        end else begin : g_no_vec
            assign vec_busy = 1'b0;
            assign vec_done = 1'b0;
            assign vec_result = 128'b0;
            assign vec_scalar_out = 32'b0;
        end
    endgenerate

    assign vec_stall = id_ex_vec_en && !vec_done && !ex_v_illegal;

    // vsetvli / vsetivli / vsetvl: LMUL = 1, SEW = 8/16/32 supported
    logic [XLEN-1:0] ex_vcfg_req, ex_vcfg_avl, ex_vcfg_vl, ex_vcfg_vtype, ex_vcfg_vlmax;
    logic            ex_vcfg_ok;
    always_comb begin
        if (id_ex_instr[31:30] == 2'b11)
            ex_vcfg_req = {{(XLEN-10){1'b0}}, id_ex_instr[29:20]};          // vsetivli
        else if (!id_ex_instr[31])
            ex_vcfg_req = {{(XLEN-11){1'b0}}, id_ex_instr[30:20]};          // vsetvli
        else
            ex_vcfg_req = ex_fwd_b;                                         // vsetvl
        ex_vcfg_ok    = (ex_vcfg_req[2:0] == 3'b000) && (ex_vcfg_req[5:3] <= 3'd2) &&
                        (ex_vcfg_req[XLEN-1:8] == {(XLEN-8){1'b0}});
        ex_vcfg_vlmax = {{(XLEN-5){1'b0}}, 5'd16} >> ex_vcfg_req[4:3];
        if (id_ex_instr[31:30] == 2'b11)
            ex_vcfg_avl = {{(XLEN-5){1'b0}}, id_ex_instr[19:15]};
        else if (id_ex_rs1_addr != 5'd0)
            ex_vcfg_avl = ex_fwd_a;
        else if (id_ex_rd != 5'd0)
            ex_vcfg_avl = {XLEN{1'b1}};                                     // VLMAX
        else
            ex_vcfg_avl = ex_vl;                                            // keep vl
        ex_vcfg_vl    = !ex_vcfg_ok ? {XLEN{1'b0}} :
                        (ex_vcfg_avl < ex_vcfg_vlmax) ? ex_vcfg_avl : ex_vcfg_vlmax;
        ex_vcfg_vtype = ex_vcfg_ok ? {{(XLEN-8){1'b0}}, ex_vcfg_req[7:0]} : {1'b1, {(XLEN-1){1'b0}}};
    end

    // CSR handling (Zicsr)
    logic [XLEN-1:0] ex_csr_rdata, ex_csr_wdata, ex_csr_src;
    logic [XLEN-1:0] ex_csr_mstatus, ex_csr_mie, ex_csr_mip, ex_csr_mtvec, ex_csr_stvec;
    logic [XLEN-1:0] ex_csr_mepc, ex_csr_sepc, ex_csr_satp;
    logic [XLEN-1:0] ex_csr_mideleg, ex_csr_medeleg;
    logic [31:0]     ex_csr_pmpcfg0;
    logic [XLEN-1:0] ex_csr_pmpaddr0, ex_csr_pmpaddr1, ex_csr_pmpaddr2, ex_csr_pmpaddr3;
    logic [1:0]      current_priv;
    logic [XLEN-1:0] trap_pc, trap_mcause, trap_mepc, trap_mtval, mip;
    logic [1:0]      trap_kind;
    logic            ex_csr_illegal, ex_csr_write_attempt;
    logic        ex_csr_write;
    logic        trap_taken;
    logic        trap_to_s;
    logic        wb_retire;

    // Machine-only read-only custom CSRs, modulo 2^32. Events overlap:
    // frontend starvation is not necessarily an exposed pipeline stall.
    logic [31:0] perf_cycles, perf_fetch, perf_data, perf_pair_wait;
    logic [31:0] perf_exec_wait, perf_pairs, perf_instructions;
    logic perf_fetch_event;
    logic [XLEN-1:0] csr_base_rdata;
    logic csr_base_illegal;
    wire perf_selected = id_ex_csr_addr >= 12'hFC0 && id_ex_csr_addr <= 12'hFC7;
`ifdef RISCV_FORMAL
    assign perf_fetch_event = 1'b0;
`else
    assign perf_fetch_event = !if_fast_local && !fetch_available && !flush_if_id;
`endif
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            perf_cycles <= 0; perf_fetch <= 0; perf_data <= 0;
            perf_pair_wait <= 0; perf_exec_wait <= 0;
            perf_pairs <= 0; perf_instructions <= 0;
        end else begin
            perf_cycles <= perf_cycles + 1;
            if (perf_fetch_event) perf_fetch <= perf_fetch + 1;
            if (mem_stall) perf_data <= perf_data + 1;
            if (pair_id_stall) perf_pair_wait <= perf_pair_wait + 1;
            if (muldiv_stall || fpu_stall || vec_stall)
                perf_exec_wait <= perf_exec_wait + 1;
            if (wb_retire) begin
                perf_instructions <= perf_instructions +
                    ((DUAL_ISSUE && id_ex_pair) ? 32'd2 : 32'd1);
                if (DUAL_ISSUE && id_ex_pair) perf_pairs <= perf_pairs + 1;
            end
        end
    end
    always_comb begin
        ex_csr_rdata = csr_base_rdata;
        ex_csr_illegal = csr_base_illegal;
        if (perf_selected) begin
            ex_csr_illegal = current_priv != 2'b11 || ex_csr_write_attempt;
            case (id_ex_csr_addr)
                12'hFC0: ex_csr_rdata = 32'h50455231; // PER1
                12'hFC1: ex_csr_rdata = perf_cycles;
                12'hFC2: ex_csr_rdata = perf_fetch;
                12'hFC3: ex_csr_rdata = perf_data;
                12'hFC4: ex_csr_rdata = perf_pair_wait;
                12'hFC5: ex_csr_rdata = perf_exec_wait;
                12'hFC6: ex_csr_rdata = perf_pairs;
                12'hFC7: ex_csr_rdata = perf_instructions;
                default: ex_csr_rdata = 0;
            endcase
        end
    end

    assign ex_csr_src = id_ex_csr_op[2] ? id_ex_csr_zimm : ex_fwd_a;
    // CSRRW/CSRRWI always write; CSRRS/C(I) write unless rs1/uimm is x0/0
    assign ex_csr_write_attempt = id_ex_csr_en &&
        ((id_ex_csr_op == CSR_RW) || (id_ex_csr_op == CSR_RWI) || (id_ex_rs1_addr != 5'b0));

    // FP / vector state updates from the instruction in EX
    logic ex_fp_flags_valid, ex_fs_dirty, ex_vcfg_write;

    csr_file #(.XLEN(XLEN), .HAS_FPU(HAS_FPU), .HAS_VEC(HAS_VEC),
               .DUAL_RETIRE(DUAL_ISSUE)) u_csr (
        .clk         (clk),
        .rst_n       (rst_n),
        .csr_write   (ex_csr_write && !mem_stall && !mmu_stall),
        .trap_write  (trap_taken),
        .trap_to_s   (trap_to_s),
        .mret_exec   (id_ex_mret_r && !mem_stall && !mmu_stall),
        .sret_exec   (id_ex_sret_r && !mem_stall && !mmu_stall),
        .retire      (wb_retire),
        .retire_second(id_ex_pair),
        .csr_addr    (id_ex_csr_addr),
        .csr_wdata   (ex_csr_wdata),
        .csr_write_attempt(ex_csr_write_attempt),
        .trap_mepc   (trap_mepc),
        .trap_mcause (trap_mcause),
        .trap_mtval  (trap_mtval),
        .trap_mip    (mip),
        .csr_rdata   (csr_base_rdata),
        .csr_illegal (csr_base_illegal),
        .fflags_set_valid(ex_fp_flags_valid),
        .fflags_set  (fpu_flags),
        .fs_dirty    (ex_fs_dirty),
        .vcfg_write  (ex_vcfg_write),
        .vcfg_vl     (ex_vcfg_vl),
        .vcfg_vtype  (ex_vcfg_vtype),
        .frm_out     (ex_frm),
        .vl_out      (ex_vl),
        .vtype_out   (ex_vtype),
        .vstart_out  (ex_vstart),
        .mstatus_out (ex_csr_mstatus),
        .mie_out     (ex_csr_mie),
        .mip_out     (ex_csr_mip),
        .mtvec_out   (ex_csr_mtvec),
        .stvec_out   (ex_csr_stvec),
        .mepc_out    (ex_csr_mepc),
        .sepc_out    (ex_csr_sepc),
        .satp_out    (ex_csr_satp),
        .current_priv_out(current_priv),
        .mcause_out  (),
        .mideleg_out (ex_csr_mideleg),
        .medeleg_out (ex_csr_medeleg),
        .pmpcfg0_out (ex_csr_pmpcfg0),
        .pmpaddr0_out(ex_csr_pmpaddr0),
        .pmpaddr1_out(ex_csr_pmpaddr1),
        .pmpaddr2_out(ex_csr_pmpaddr2),
        .pmpaddr3_out(ex_csr_pmpaddr3)
    );

    always_comb begin
        ex_csr_wdata = ex_csr_rdata;
        ex_csr_write = 1'b0;

        if (id_ex_csr_en) begin
            case (id_ex_csr_op)
                CSR_RW, CSR_RWI: begin
                    ex_csr_wdata = ex_csr_src;
                    ex_csr_write = 1'b1;
                end
                CSR_RS, CSR_RSI: begin
                    ex_csr_wdata = ex_csr_rdata | ex_csr_src;
                    ex_csr_write = (ex_csr_src != {XLEN{1'b0}});
                end
                CSR_RC, CSR_RCI: begin
                    ex_csr_wdata = ex_csr_rdata & ~ex_csr_src;
                    ex_csr_write = (ex_csr_src != {XLEN{1'b0}});
                end
                default: begin
                    ex_csr_wdata = ex_csr_rdata;
                    ex_csr_write = 1'b0;
                end
            endcase
        end
    end

    // Branch target address
    logic [XLEN-1:0] ex_branch_target;
    assign ex_branch_target = id_ex_pc + id_ex_imm;

    // JALR target (rs1 + imm, LSB cleared)
    logic [XLEN-1:0] ex_jalr_target;
    logic [XLEN-1:0] jalr_sum;
    assign jalr_sum = ex_fwd_a + id_ex_imm;
    assign ex_jalr_target = {jalr_sum[XLEN-1:1], 1'b0};

    // Branch taken logic (decode funct3 for BEQ/BNE/BLT/BGE/BLTU/BGEU)
    logic branch_taken;
    logic ex_signed_lt, ex_unsigned_lt;
    assign ex_signed_lt   = ($signed(ex_fwd_a) < $signed(ex_fwd_b));
    assign ex_unsigned_lt = (ex_fwd_a < ex_fwd_b);

    always_comb begin
        branch_taken = 1'b0;
        if (id_ex_branch) begin
            case (id_ex_funct3)
                3'b000: branch_taken = ex_zero;               // BEQ
                3'b001: branch_taken = ~ex_zero;              // BNE
                3'b100: branch_taken = ex_signed_lt;          // BLT
                3'b101: branch_taken = ~ex_signed_lt;         // BGE
                3'b110: branch_taken = ex_unsigned_lt;        // BLTU
                3'b111: branch_taken = ~ex_unsigned_lt;       // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    logic control_taken, branch_mispredict;
    logic [XLEN-1:0] control_target, fallthrough_target;
    assign control_taken = branch_taken || id_ex_jump;
    assign control_target = (id_ex_jump && id_ex_opcode == OP_JALR) ? ex_jalr_target : ex_branch_target;
    assign fallthrough_target = id_ex_pc + (id_ex_pair ? 8 : 4);
    // A taken prediction for an instruction that is not a branch/jump (a stale
    // BTB entry, e.g. after the code at that address was rewritten) is also a
    // misprediction: fetch must resume at the fall-through PC.
    assign branch_mispredict = (id_ex_branch || id_ex_jump) ?
                               ((id_ex_pred_taken != control_taken) ||
                                (control_taken && id_ex_pred_taken &&
                                 (id_ex_pred_target != control_target))) :
                               id_ex_pred_taken;

    // PC selection and flush logic
    // When branch_taken or jump asserts in EX stage:
    //   - flush_ex clears ID/EX immediately (prevents next instr from entering EX)
    //   - flush_if_id clears IF/ID immediately (prevents PC update)
    //   - flush_ex_mem_r delays the clearing of EX/MEM by 1 cycle
    // This ensures:
    //   1. Branch/jump results latch normally into EX/MEM
    //   2. Instructions after branch/jump don't write to registers
    //   3. JAL/JALR link register still gets PC+4
    
    // Interrupt handling (precise: retire current EX instruction)
    logic [XLEN-1:0] ex_ret_pc;
    always_comb begin
        if (id_ex_jump && id_ex_opcode == 7'b1100111)
            ex_ret_pc = ex_jalr_target;
        else if (id_ex_jump)
            ex_ret_pc = ex_branch_target;
        else if (branch_taken)
            ex_ret_pc = ex_branch_target;
        else
            ex_ret_pc = fallthrough_target;
    end

    // MMU page-fault signals. The transaction-bus SoC can now run the shared
    // Sv32 walker; M-mode and satp.MODE=0 remain direct physical addressing.
    logic mem_page_fault;
    logic mem_page_fault_store;

    logic page_fault_exception;
    logic [XLEN-1:0] page_fault_cause;
    logic [XLEN-1:0] exc_pc;
    logic pmp_inst_allow, pmp_data_allow, pmp_inst_fault, pmp_data_fault, pmp_access_fault;
    logic bus_inst_fault, bus_data_fault;
    logic [XLEN-1:0] pmp_access_cause, pmp_access_addr;
    logic [3:0] pmp_data_size;
    assign page_fault_exception = inst_fault || mem_page_fault;
    assign page_fault_cause = inst_fault ? EXC_INST_PAGE :
                              mem_page_fault_store ? EXC_STORE_PAGE : EXC_LOAD_PAGE;

    always_comb begin
        if (bus_inst_fault)
            exc_pc = id_ex_pc;
        else if (inst_fault || pmp_inst_fault)
            exc_pc = pc;
        else if (mem_page_fault || pmp_data_fault || bus_data_fault)
            exc_pc = ex_mem_pc;
        else
            exc_pc = id_ex_pc;
    end

    // Scalar unaligned accesses are completed by the banked SoC BRAM.
    logic ex_misaligned_mem, ex_misaligned_load, ex_misaligned_store, ex_misaligned_fetch;
    always_comb begin
        case (id_ex_funct3[1:0])
            2'b00:   ex_misaligned_mem = 1'b0;                         // byte
            2'b01:   ex_misaligned_mem = ex_alu_result_raw[0];         // halfword
            2'b10:   ex_misaligned_mem = |ex_alu_result_raw[1:0];      // word
            default: ex_misaligned_mem = |ex_alu_result_raw[2:0];      // doubleword
        endcase
    end
    // Scalar unaligned accesses are completed by the banked SoC BRAM. The
    // RVFI harness uses its standard aligned-memory model, which cannot
    // describe a single access spanning two words, so that build retains the
    // architectural trap behavior for its proof boundary.
`ifdef RISCV_FORMAL
    assign ex_misaligned_load  = id_ex_mem_read  && ex_misaligned_mem;
    assign ex_misaligned_store = id_ex_mem_write && ex_misaligned_mem;
`else
    assign ex_misaligned_load  = ex_v_load  && ex_v_mis;
    assign ex_misaligned_store = ex_v_store && ex_v_mis;
`endif
    // Taken jump/branch to an address that is not 4-byte aligned (no C extension)
    assign ex_misaligned_fetch = control_taken && control_target[1];

    always_comb begin
        case (id_ex_funct3[1:0])
            2'b00:   pmp_data_size = 4'd1;
            2'b01:   pmp_data_size = 4'd2;
            2'b10:   pmp_data_size = 4'd4;
            default: pmp_data_size = (XLEN == 64) ? 4'd8 : 4'd4;
        endcase
    end

    pmp_unit #(.XLEN(XLEN)) u_pmp_inst (
        .addr(pc), .access_size(4'd4),
        .access_r(1'b0), .access_w(1'b0), .access_x(1'b1),
        .current_priv(current_priv), .pmpcfg0(ex_csr_pmpcfg0),
        .pmpaddr0(ex_csr_pmpaddr0), .pmpaddr1(ex_csr_pmpaddr1),
        .pmpaddr2(ex_csr_pmpaddr2), .pmpaddr3(ex_csr_pmpaddr3),
        .allow(pmp_inst_allow)
    );

    pmp_unit #(.XLEN(XLEN)) u_pmp_data (
        .addr(ex_alu_result_raw), .access_size(pmp_data_size),
        .access_r(id_ex_mem_read), .access_w(id_ex_mem_write), .access_x(1'b0),
        .current_priv(current_priv), .pmpcfg0(ex_csr_pmpcfg0),
        .pmpaddr0(ex_csr_pmpaddr0), .pmpaddr1(ex_csr_pmpaddr1),
        .pmpaddr2(ex_csr_pmpaddr2), .pmpaddr3(ex_csr_pmpaddr3),
        .allow(pmp_data_allow)
    );

    assign pmp_inst_fault   = !pmp_inst_allow;
    assign pmp_data_fault   = (id_ex_mem_read || id_ex_mem_write) && !pmp_data_allow;
    assign bus_inst_fault   = id_ex_bus_error && id_ex_valid;
    assign pmp_access_fault = pmp_inst_fault || pmp_data_fault ||
                              bus_inst_fault || bus_data_fault;
    assign pmp_access_cause = (pmp_inst_fault || bus_inst_fault) ?
                              {{(XLEN-2){1'b0}}, 2'd1} :
                              ((bus_data_fault ? ex_mem_mem_write : id_ex_mem_write) ?
                               {{(XLEN-3){1'b0}}, 3'd7} :
                               {{(XLEN-3){1'b0}}, 3'd5});
    assign pmp_access_addr  = bus_inst_fault ? id_ex_pc :
                              pmp_inst_fault ? pc :
                              bus_data_fault ? ex_mem_alu_result : ex_alu_result_raw;

    // EX-stage exceptions and interrupts are only taken while MEM is not
    // frozen, otherwise the trap redirect could not update the PC.
    logic ex_can_trap, irq_enable, ex_illegal;
    assign ex_can_trap = !mem_stall && !mmu_stall_raw;
    assign ex_illegal  = id_ex_illegal ||
                         (id_ex_csr_en  && ex_csr_illegal) ||
                         (id_ex_mret_r  && (current_priv != 2'b11)) ||
                         (id_ex_sret_r  && ((current_priv == 2'b00) ||
                          (current_priv == 2'b01 && ex_csr_mstatus[22]))) ||
                         (id_ex_sfence  && ((current_priv == 2'b00) ||
                          (current_priv == 2'b01 && ex_csr_mstatus[20]))) ||
                         ex_f_illegal || ex_v_illegal;
    // Interrupts complete the EX instruction and resume after it, so EX must
    // hold a real instruction that has finished and has no side effects that
    // the trap would discard (CSR writes, xRET, fences).
    assign irq_enable  = id_ex_valid && ex_can_trap &&
                         !muldiv_stall && !fpu_stall && !vec_stall &&
                         !id_ex_csr_en && !id_ex_mret_r && !id_ex_sret_r &&
                         !id_ex_sfence && !id_ex_fencei && !ex_v_cfg;

    interrupt_unit #(.XLEN(XLEN)) u_int (
        .clk             (clk),
        .rst_n           (rst_n),
        .pc              (exc_pc),
        .next_pc         (ex_ret_pc),
        .instr           (id_ex_instr),
        .instr_valid     (ex_can_trap),
        .current_priv    (current_priv),
        .illegal_instr   (ex_illegal),
        .ecall           (id_ex_ecall_r),
        .ebreak          (id_ex_ebreak_r),
        .misaligned_fetch(ex_misaligned_fetch),
        .misaligned_load (ex_misaligned_load),
        .misaligned_store(ex_misaligned_store),
        .misaligned_addr (ex_misaligned_fetch ? control_target :
                          (ex_v_load || ex_v_store) ? ex_fwd_a : ex_alu_result_raw),
        .page_fault      (page_fault_exception),
        .page_fault_cause(page_fault_cause),
        .page_fault_addr (inst_fault ? pc : ex_mem_alu_result),
        .access_fault    (pmp_access_fault),
        .access_fault_cause(pmp_access_cause),
        .access_fault_addr(pmp_access_addr),
        .ext_interrupt   (ext_interrupt),
        .timer_interrupt (timer_interrupt),
        .software_interrupt(software_interrupt),
        .irq_enable      (irq_enable),
        .mstatus         (ex_csr_mstatus),
        .mie             (ex_csr_mie),
        .mip             (ex_csr_mip),
        .mtvec           (ex_csr_mtvec),
        .stvec           (ex_csr_stvec),
        .mideleg         (ex_csr_mideleg),
        .medeleg         (ex_csr_medeleg),
        .mcause_out      (trap_mcause),
        .mepc_out        (trap_mepc),
        .mtval_out       (trap_mtval),
        .mip_out         (mip),
        .trap_taken      (trap_taken),
        .trap_to_s       (trap_to_s),
        .trap_pc         (trap_pc),
        .trap_cause      (trap_kind)
    );

    // A fault in MEM also kills the younger EX instruction. Otherwise an ALU
    // operation behind a failed load can commit here and again after mret.
    logic ex_exc_taken;
    assign ex_exc_taken = trap_taken && (trap_kind == 2'b01) &&
                          ((!page_fault_exception && !pmp_access_fault) ||
                           bus_data_fault || mem_page_fault || bus_inst_fault || pmp_data_fault);

    // FP flags / FS and vector configuration commit when the EX instruction completes
    assign ex_fp_flags_valid = id_ex_fp_en && fpu_done && !ex_f_illegal && !trap_taken;
    assign ex_fs_dirty       = ex_f_any && id_ex_valid && !ex_f_illegal && !trap_taken &&
                               !fpu_stall && !mem_stall && !mmu_stall;
    assign ex_vcfg_write     = ex_v_cfg && id_ex_valid && !trap_taken && !mem_stall && !mmu_stall;

    logic flush_ex, flush_ex_mem;
    logic flush_ex_mem_r;  // Delayed by 1 cycle to flush instruction AFTER branch

    // Redirect fetch only on a misprediction (a correctly predicted taken
    // branch keeps the fetched target), xRET, SFENCE.VMA / FENCE.I (refetch
    // younger instructions), or a trap. Only once the EX instruction has
    // finished: never while MEM is frozen or a multi-cycle unit is busy (a
    // stale prediction can sit on a MUL/DIV/FP/vector instruction).
    logic ex_redirect;
    assign ex_redirect = (branch_mispredict || id_ex_mret_r || id_ex_sret_r || id_ex_sfence || id_ex_fencei) &&
                         !mem_stall && !mmu_stall && !muldiv_stall && !fpu_stall && !vec_stall;
    assign flush_ex    = ex_redirect || trap_taken;
    assign flush_if_id = flush_ex;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            flush_ex_mem_r <= 1'b0;
        else
            flush_ex_mem_r <= flush_ex;
    end

    assign flush_ex_mem = flush_ex_mem_r;

    always_comb begin
        if (trap_taken)
            pc_next = trap_pc;
        else if (id_ex_mret_r)
            pc_next = ex_csr_mepc;
        else if (id_ex_sret_r)
            pc_next = ex_csr_sepc;
        else if (branch_mispredict)
            pc_next = control_taken ? control_target : fallthrough_target;
        else if (id_ex_sfence || id_ex_fencei)
            pc_next = fallthrough_target;
        else if (predict_valid && predict_taken)
            pc_next = predict_target;
        else
            pc_next = fetch_pair ? pc + 8 : pc_plus4;
    end

    // JAL/JALR link value  (PC+4 written to rd)
    logic [XLEN-1:0] ex_link_val;
    assign ex_link_val = id_ex_pc + {{(XLEN-32){1'b0}}, 32'd4};

    // ===================================================
    //  EX / MEM  pipeline register
    // ===================================================
    logic [XLEN-1:0] ex_mem_alu_result, ex_mem_rs2, ex_mem_pc_plus4, ex_mem_pc;
    logic [31:0] ex_mem_fp_rs2, ex_mem_fp_result;
    logic [127:0] ex_mem_vec_result;
    logic [4:0]  ex_mem_rd;
    logic [2:0]  ex_mem_funct3;
    logic        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write;
    logic        ex_mem_mem_to_reg, ex_mem_zero, ex_mem_jump;
    logic        ex_mem_csr_en;
    logic        ex_mem_fp_reg_write, ex_mem_fp_load, ex_mem_fp_store;
    logic        ex_mem_vec_reg_write;
    logic [XLEN-1:0] ex_mem_csr_rdata;
    logic        ex_mem_valid, ex_mem_fast_local_data;
    logic        ex_fast_local_data;

    // Paging-disabled accesses to the 64 KiB on-chip RAM can use the original
    // one-cycle data path. Paged accesses stay on the MMU/transaction path.
    assign ex_fast_local_data = FAST_LOCAL_DMEM && id_ex_valid &&
                                (id_ex_mem_read || id_ex_mem_write) &&
                                ({1'b0, ex_result[31:0]} +
                                 ((id_ex_funct3[1:0] == 0) ? 33'd1 :
                                  (id_ex_funct3[1:0] == 1) ? 33'd2 : 33'd4) <= LOCAL_MEM_BYTES) &&
                                !ex_csr_satp[31] && pmp_data_allow &&
                                !ex_f_illegal;

`ifndef RISCV_FORMAL
    assign dtcm_addr  = ex_result[31:0];
    assign dtcm_wdata = id_ex_fp_store ? id_ex_fp_rs2 : ex_fwd_b[31:0];
    assign dtcm_wstrb = (id_ex_funct3[1:0] == 2'b00) ? 4'b0001 :
                        (id_ex_funct3[1:0] == 2'b01) ? 4'b0011 : 4'b1111;
    assign dtcm_rd_en = ex_fast_local_data && id_ex_mem_read && id_ex_write &&
                        !ex_exc_taken;
    assign dtcm_wr_en = ex_fast_local_data && id_ex_mem_write && id_ex_write &&
                        !ex_exc_taken;
`endif

    assign ex_mem_fwd_data = ex_mem_csr_en ? ex_mem_csr_rdata :
                             ex_mem_jump   ? ex_mem_pc_plus4  :
                                             ex_mem_alu_result;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_alu_result <= {XLEN{1'b0}};
            ex_mem_rs2        <= {XLEN{1'b0}};
            ex_mem_fp_rs2     <= 32'b0;
            ex_mem_fp_result  <= 32'b0;
            ex_mem_vec_result <= 128'b0;
            ex_mem_pc_plus4   <= {XLEN{1'b0}};
            ex_mem_pc         <= {XLEN{1'b0}};
            ex_mem_rd         <= 5'b0;
            ex_mem_funct3     <= 3'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_mem_to_reg <= 1'b0;
            ex_mem_zero       <= 1'b0;
            ex_mem_jump       <= 1'b0;
            ex_mem_csr_en     <= 1'b0;
            ex_mem_fp_reg_write <= 1'b0;
            ex_mem_fp_load    <= 1'b0;
            ex_mem_fp_store   <= 1'b0;
            ex_mem_vec_reg_write <= 1'b0;
            ex_mem_csr_rdata  <= {XLEN{1'b0}};
            ex_mem_valid      <= 1'b0;
            ex_mem_fast_local_data <= 1'b0;
        end else if (mem_stall || mmu_stall) begin
            ex_mem_alu_result <= ex_mem_alu_result;
            ex_mem_rs2        <= ex_mem_rs2;
            ex_mem_fp_rs2     <= ex_mem_fp_rs2;
            ex_mem_fp_result  <= ex_mem_fp_result;
            ex_mem_vec_result <= ex_mem_vec_result;
            ex_mem_pc_plus4   <= ex_mem_pc_plus4;
            ex_mem_pc         <= ex_mem_pc;
            ex_mem_rd         <= ex_mem_rd;
            ex_mem_funct3     <= ex_mem_funct3;
            ex_mem_reg_write  <= ex_mem_reg_write;
            ex_mem_mem_read   <= ex_mem_mem_read;
            ex_mem_mem_write  <= ex_mem_mem_write;
            ex_mem_mem_to_reg <= ex_mem_mem_to_reg;
            ex_mem_zero       <= ex_mem_zero;
            ex_mem_jump       <= ex_mem_jump;
            ex_mem_csr_en     <= ex_mem_csr_en;
            ex_mem_fp_reg_write <= ex_mem_fp_reg_write;
            ex_mem_fp_load    <= ex_mem_fp_load;
            ex_mem_fp_store   <= ex_mem_fp_store;
            ex_mem_vec_reg_write <= ex_mem_vec_reg_write;
            ex_mem_csr_rdata  <= ex_mem_csr_rdata;
            ex_mem_valid      <= ex_mem_valid;
            ex_mem_fast_local_data <= ex_mem_fast_local_data;
        end else if (muldiv_stall || fpu_stall || vec_stall) begin
            // Hold EX stage and insert a bubble into MEM while mul/div completes
            ex_mem_alu_result <= {XLEN{1'b0}};
            ex_mem_rs2        <= {XLEN{1'b0}};
            ex_mem_fp_rs2     <= 32'b0;
            ex_mem_fp_result  <= 32'b0;
            ex_mem_vec_result <= 128'b0;
            ex_mem_pc_plus4   <= {XLEN{1'b0}};
            ex_mem_pc         <= {XLEN{1'b0}};
            ex_mem_rd         <= 5'b0;
            ex_mem_funct3     <= 3'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_mem_to_reg <= 1'b0;
            ex_mem_zero       <= 1'b0;
            ex_mem_jump       <= 1'b0;
            ex_mem_csr_en     <= 1'b0;
            ex_mem_fp_reg_write <= 1'b0;
            ex_mem_fp_load    <= 1'b0;
            ex_mem_fp_store   <= 1'b0;
            ex_mem_vec_reg_write <= 1'b0;
            ex_mem_csr_rdata  <= {XLEN{1'b0}};
            ex_mem_valid      <= 1'b0;
            ex_mem_fast_local_data <= 1'b0;
        end else if (ex_exc_taken) begin
            // The EX instruction raised an exception: it must not retire
            // Hold EX stage and insert a bubble into MEM while mul/div completes
            ex_mem_alu_result <= {XLEN{1'b0}};
            ex_mem_rs2        <= {XLEN{1'b0}};
            ex_mem_fp_rs2     <= 32'b0;
            ex_mem_fp_result  <= 32'b0;
            ex_mem_vec_result <= 128'b0;
            ex_mem_pc_plus4   <= {XLEN{1'b0}};
            ex_mem_pc         <= {XLEN{1'b0}};
            ex_mem_rd         <= 5'b0;
            ex_mem_funct3     <= 3'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_mem_to_reg <= 1'b0;
            ex_mem_zero       <= 1'b0;
            ex_mem_jump       <= 1'b0;
            ex_mem_csr_en     <= 1'b0;
            ex_mem_fp_reg_write <= 1'b0;
            ex_mem_fp_load    <= 1'b0;
            ex_mem_fp_store   <= 1'b0;
            ex_mem_vec_reg_write <= 1'b0;
            ex_mem_csr_rdata  <= {XLEN{1'b0}};
            ex_mem_valid      <= 1'b0;
            ex_mem_fast_local_data <= 1'b0;
        end else if (flush_ex_mem) begin
            // When flushing, clear control signals but latch data normally
            // This prevents accidental writes from delayed pipeline instructions
            ex_mem_alu_result <= ex_result;
            ex_mem_rs2        <= ex_fwd_b;
            ex_mem_fp_rs2     <= id_ex_fp_rs2;
            ex_mem_fp_result  <= fpu_result;
            ex_mem_vec_result <= vec_result;
            ex_mem_pc_plus4   <= ex_link_val;
            ex_mem_pc         <= id_ex_pc;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_funct3     <= id_ex_funct3;
            ex_mem_reg_write  <= 1'b0;           // Disable write for flushed instruction
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_mem_to_reg <= 1'b0;
            ex_mem_zero       <= ex_zero;
            ex_mem_jump       <= 1'b0;
            ex_mem_csr_en     <= 1'b0;
            ex_mem_fp_reg_write <= 1'b0;
            ex_mem_fp_load    <= 1'b0;
            ex_mem_fp_store   <= 1'b0;
            ex_mem_vec_reg_write <= 1'b0;
            ex_mem_csr_rdata  <= ex_csr_rdata;
            ex_mem_valid      <= 1'b0;
            ex_mem_fast_local_data <= 1'b0;
        end else begin
            ex_mem_alu_result <= ex_result;
            ex_mem_rs2        <= ex_fwd_b;
            ex_mem_fp_rs2     <= id_ex_fp_rs2;
            ex_mem_fp_result  <= fpu_result;
            ex_mem_vec_result <= vec_result;
            ex_mem_pc_plus4   <= ex_link_val;
            ex_mem_pc         <= id_ex_pc;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_funct3     <= id_ex_funct3;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_mem_to_reg <= id_ex_mem_to_reg;
            ex_mem_zero       <= ex_zero;
            ex_mem_jump       <= id_ex_jump;
            ex_mem_csr_en     <= id_ex_csr_en;
            ex_mem_fp_reg_write <= id_ex_fp_reg_write;
            ex_mem_fp_load    <= id_ex_fp_load;
            ex_mem_fp_store   <= id_ex_fp_store;
            ex_mem_vec_reg_write <= id_ex_vec_reg_write;
            ex_mem_csr_rdata  <= ex_csr_rdata;
            ex_mem_valid      <= id_ex_valid;
            ex_mem_fast_local_data <= ex_fast_local_data;
        end
    end

    // ===================================================
    //  MEMORY STAGE - variable-latency transaction bus
    // ===================================================

    logic [XLEN-1:0] mem_rd_data;
    logic [XLEN-1:0] data_paddr;
    logic             mmu_stall_raw;
    logic [31:0]      load_source;
    logic [31:0]      load_data32;
    logic [7:0]       load_byte;
    logic [15:0]      load_half;

`ifdef RISCV_FORMAL
    // Preserve the established fixed-latency formal memory model.
    assign data_paddr    = ex_result;
    assign inst_paddr    = pc;
    assign inst_ready    = 1'b1;
    assign inst_fault    = 1'b0;
    assign mem_page_fault = 1'b0;
    assign mem_page_fault_store = 1'b0;
    assign mmu_stall     = 1'b0;
    assign mmu_stall_raw = 1'b0;
    assign mem_stall     = 1'b0;
    assign bus_data_fault = 1'b0;

    assign dmem_addr   = data_paddr[31:0];
    assign dmem_wdata  = id_ex_fp_store ? id_ex_fp_rs2 : ex_fwd_b[31:0];
    assign dmem_rd_en  = id_ex_mem_read  && !ex_f_illegal && pmp_data_allow;
    assign dmem_wr_en  = id_ex_mem_write && !ex_f_illegal && pmp_data_allow;
    assign dmem_funct3 = id_ex_funct3;
    assign load_source = dmem_rdata;
`else
    logic        mem_access;
    logic        local_mem_access;
    logic        data_txn_pending;
    logic        data_rsp_done;
    logic        data_rsp_error;
    logic [31:0] data_rsp_value;
    logic        mmu_data_ready;
    logic        mmu_data_fault;
    logic        mmu_inst_ready;
    logic        mmu_inst_fault;
    logic        mmu_ptw_read;
    logic [31:0] mmu_ptw_addr;
    logic        fetch_translation_req;

    assign mem_access = ex_mem_valid && (ex_mem_mem_read || ex_mem_mem_write);
    assign local_mem_access = mem_access && ex_mem_fast_local_data;
    assign fetch_translation_req = !if_fast_local && rst_n &&
                                   !ifetch_request && !ifetch_pending && !ifetch_valid;

    generate
        if (ENABLE_MMU) begin : gen_mmu
            mmu #(.XLEN(XLEN), .PTW_HANDSHAKE(1'b1)) u_mmu (
                .clk          (clk),
                .rst_n        (rst_n),
                .satp         (ex_csr_satp),
                .mstatus      (ex_csr_mstatus),
                .current_priv (current_priv),
                .sfence       (id_ex_sfence && !mem_stall && !mmu_stall),
                .inst_vaddr   (pc),
                .inst_req     (fetch_translation_req),
                .inst_paddr   (inst_paddr),
                .inst_ready   (mmu_inst_ready),
                .inst_fault   (mmu_inst_fault),
                .data_vaddr   (ex_mem_alu_result),
                .data_req     (mem_access && !local_mem_access && !data_rsp_done),
                .data_write   (ex_mem_mem_write),
                .data_paddr   (data_paddr),
                .data_ready   (mmu_data_ready),
                .data_fault   (mmu_data_fault),
                .stall        (),
                .ptw_read     (mmu_ptw_read),
                .ptw_addr     (mmu_ptw_addr),
                .ptw_rdata    (ptw_rsp_rdata),
                .ptw_req_valid(ptw_req_valid),
                .ptw_req_ready(ptw_req_ready),
                .ptw_rsp_valid(ptw_rsp_valid),
                .ptw_rsp_err  (ptw_rsp_err),
                .ptw_rsp_rdata(ptw_rsp_rdata)
            );
        end else begin : gen_no_mmu
            assign inst_paddr    = pc;
            assign data_paddr    = ex_mem_alu_result;
            assign mmu_inst_ready = 1'b1;
            assign mmu_inst_fault = 1'b0;
            assign mmu_data_ready = 1'b1;
            assign mmu_data_fault = 1'b0;
            assign mmu_ptw_read   = 1'b0;
            assign mmu_ptw_addr   = 32'b0;
            assign ptw_req_valid  = 1'b0;
        end
    endgenerate

    assign inst_ready = mmu_inst_ready;
    assign inst_fault = mmu_inst_fault;
    assign mem_page_fault = mem_access && !local_mem_access && mmu_data_fault;
    assign mem_page_fault_store = ex_mem_mem_write;
    assign mmu_stall_raw = (fetch_translation_req && !mmu_inst_ready && !mmu_inst_fault) ||
                           (mem_access && !local_mem_access &&
                            !mmu_data_ready && !mmu_data_fault);
    assign mmu_stall = mmu_stall_raw && !trap_taken;

    assign ptw_req_addr  = mmu_ptw_addr;
    assign ptw_req_write = 1'b0;
    assign ptw_req_wstrb = 4'b0000;
    assign ptw_req_wdata = 32'b0;
    assign ptw_req_size  = 2'd2;
    assign ptw_rsp_ready = 1'b1;

    assign dbus_req_valid = mem_access && !local_mem_access &&
                            mmu_data_ready && !mmu_data_fault &&
                            !data_txn_pending && !data_rsp_done;
    assign dbus_req_addr  = data_paddr[31:0];
    assign dbus_req_write = ex_mem_mem_write;
    assign dbus_req_wdata = ex_mem_fp_store ? ex_mem_fp_rs2 : ex_mem_rs2[31:0];
    assign dbus_req_size  = (ex_mem_funct3[1:0] == 2'b00) ? 2'd0 :
                            (ex_mem_funct3[1:0] == 2'b01) ? 2'd1 : 2'd2;
    assign dbus_req_wstrb = !ex_mem_mem_write ? 4'b0000 :
                            (dbus_req_size == 2'd0) ? 4'b0001 :
                            (dbus_req_size == 2'd1) ? 4'b0011 : 4'b1111;
    assign dbus_rsp_ready = data_txn_pending;
    assign mem_stall = mem_access && !local_mem_access &&
                       mmu_data_ready && !mmu_data_fault && !data_rsp_done;
    assign bus_data_fault = data_rsp_done && data_rsp_error &&
                            mem_access && !local_mem_access;
    assign load_source = local_mem_access ? dtcm_rdata : data_rsp_value;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_txn_pending <= 1'b0;
            data_rsp_done    <= 1'b0;
            data_rsp_error   <= 1'b0;
            data_rsp_value   <= 32'b0;
        end else begin
            if (data_rsp_done) begin
                data_rsp_done  <= 1'b0;
                data_rsp_error <= 1'b0;
            end
            if (dbus_req_valid && dbus_req_ready)
                data_txn_pending <= 1'b1;
            if (dbus_rsp_valid && dbus_rsp_ready) begin
                data_txn_pending <= 1'b0;
                data_rsp_done    <= 1'b1;
                data_rsp_error   <= dbus_rsp_err;
                data_rsp_value   <= dbus_rsp_rdata;
            end
            if (flush_ex && !mem_stall && !data_txn_pending && !dbus_rsp_valid) begin
                data_rsp_done  <= 1'b0;
                data_rsp_error <= 1'b0;
            end
        end
    end
`endif

    // Bus read data is right-justified for the exact byte address.
    always_comb begin
`ifdef RISCV_FORMAL
        case (ex_mem_alu_result[1:0])
            2'b00: load_byte = load_source[7:0];
            2'b01: load_byte = load_source[15:8];
            2'b10: load_byte = load_source[23:16];
            default: load_byte = load_source[31:24];
        endcase
        load_half = ex_mem_alu_result[1] ? load_source[31:16] : load_source[15:0];
`else
        load_byte = load_source[7:0];
        load_half = load_source[15:0];
`endif
        case (ex_mem_funct3)
            3'b000:  load_data32 = {{24{load_byte[7]}}, load_byte};
            3'b001:  load_data32 = {{16{load_half[15]}}, load_half};
            3'b100:  load_data32 = {24'b0, load_byte};
            3'b101:  load_data32 = {16'b0, load_half};
            default: load_data32 = load_source;
        endcase
    end

    assign mem_rd_data = {{(XLEN-32){1'b0}}, load_data32};

    // ===================================================
    //  MEM / WB  pipeline register
    // ===================================================
    logic [XLEN-1:0] mem_wb_alu_result, mem_wb_mem_data, mem_wb_pc_plus4;
    logic [XLEN-1:0] mem_wb_csr_rdata;
    logic [31:0] mem_wb_fp_result;
    logic [127:0] mem_wb_vec_result;
    logic        mem_wb_mem_to_reg, mem_wb_jump, mem_wb_csr_en;
    logic        mem_wb_fp_reg_write, mem_wb_fp_load, mem_wb_vec_reg_write;
    logic        mem_wb_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_alu_result <= {XLEN{1'b0}};
            mem_wb_mem_data   <= {XLEN{1'b0}};
            mem_wb_pc_plus4   <= {XLEN{1'b0}};
            wb_rd_addr        <= 5'b0;
            wb_reg_write      <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
            mem_wb_jump       <= 1'b0;
            mem_wb_csr_en     <= 1'b0;
            mem_wb_csr_rdata  <= {XLEN{1'b0}};
            mem_wb_fp_result  <= 32'b0;
            mem_wb_vec_result <= 128'b0;
            fp_wb_rd          <= 5'b0;
            fp_wb_write       <= 1'b0;
            vec_wb_rd         <= 5'b0;
            vec_wb_write      <= 1'b0;
            mem_wb_fp_reg_write <= 1'b0;
            mem_wb_fp_load    <= 1'b0;
            mem_wb_vec_reg_write <= 1'b0;
            mem_wb_valid      <= 1'b0;
        end else if (mem_stall || mmu_stall) begin
            mem_wb_alu_result <= {XLEN{1'b0}};
            mem_wb_mem_data   <= {XLEN{1'b0}};
            mem_wb_pc_plus4   <= {XLEN{1'b0}};
            wb_rd_addr        <= 5'b0;
            wb_reg_write      <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
            mem_wb_jump       <= 1'b0;
            mem_wb_csr_en     <= 1'b0;
            mem_wb_csr_rdata  <= {XLEN{1'b0}};
            mem_wb_fp_result  <= 32'b0;
            mem_wb_vec_result <= 128'b0;
            fp_wb_rd          <= 5'b0;
            fp_wb_write       <= 1'b0;
            vec_wb_rd         <= 5'b0;
            vec_wb_write      <= 1'b0;
            mem_wb_fp_reg_write <= 1'b0;
            mem_wb_fp_load    <= 1'b0;
            mem_wb_vec_reg_write <= 1'b0;
            mem_wb_valid      <= 1'b0;
        end else if (bus_data_fault || mem_page_fault) begin
            mem_wb_alu_result <= {XLEN{1'b0}};
            mem_wb_mem_data   <= {XLEN{1'b0}};
            mem_wb_pc_plus4   <= {XLEN{1'b0}};
            wb_rd_addr        <= 5'b0;
            wb_reg_write      <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
            mem_wb_jump       <= 1'b0;
            mem_wb_csr_en     <= 1'b0;
            mem_wb_csr_rdata  <= {XLEN{1'b0}};
            mem_wb_fp_result  <= 32'b0;
            mem_wb_vec_result <= 128'b0;
            fp_wb_rd          <= 5'b0;
            fp_wb_write       <= 1'b0;
            vec_wb_rd         <= 5'b0;
            vec_wb_write      <= 1'b0;
            mem_wb_fp_reg_write <= 1'b0;
            mem_wb_fp_load    <= 1'b0;
            mem_wb_vec_reg_write <= 1'b0;
            mem_wb_valid      <= 1'b0;
        end else begin
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_data   <= mem_rd_data;
            mem_wb_pc_plus4   <= ex_mem_pc_plus4;
            wb_rd_addr        <= ex_mem_rd;
            wb_reg_write      <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
            mem_wb_jump       <= ex_mem_jump;
            mem_wb_csr_en     <= ex_mem_csr_en;
            mem_wb_csr_rdata  <= ex_mem_csr_rdata;
            mem_wb_fp_result  <= ex_mem_fp_result;
            mem_wb_vec_result <= ex_mem_vec_result;
            fp_wb_rd          <= ex_mem_rd;
            fp_wb_write       <= ex_mem_fp_reg_write;
            vec_wb_rd         <= ex_mem_rd;
            vec_wb_write      <= ex_mem_vec_reg_write;
            mem_wb_fp_reg_write <= ex_mem_fp_reg_write;
            mem_wb_fp_load    <= ex_mem_fp_load;
            mem_wb_vec_reg_write <= ex_mem_vec_reg_write;
            mem_wb_valid      <= ex_mem_valid;
        end
    end

    // ===================================================
    //  WRITEBACK STAGE
    // ===================================================
    always_comb begin
        if (mem_wb_csr_en)
            wb_wr_data = mem_wb_csr_rdata;         // CSR read value
        else if (mem_wb_jump)
            wb_wr_data = mem_wb_pc_plus4;        // JAL/JALR stores PC+4
        else if (mem_wb_mem_to_reg)
            wb_wr_data = mem_wb_mem_data;         // LOAD
        else
            wb_wr_data = mem_wb_alu_result;       // ALU / LUI / AUIPC
    end

    // instret counts an instruction when it leaves EX without an exception
    // (the stage that also reads and writes CSRs, so counter reads/writes
    // see a consistent count).
    assign wb_retire = id_ex_valid && !ex_exc_taken && !mem_stall && !mmu_stall &&
                       !muldiv_stall && !fpu_stall && !vec_stall;
    assign fp_wb_data = mem_wb_fp_load ? mem_wb_mem_data[31:0] : mem_wb_fp_result;
    assign vec_wb_data = mem_wb_vec_result;

    // ===================================================
    //  Debug outputs
    // ===================================================
    assign dbg_pc          = pc[31:0];
    assign dbg_instr       = if_instr;
    assign dbg_alu_result  = ex_result[31:0];
    assign dbg_reg_rd_data = wb_wr_data[31:0];

`ifdef RISCV_FORMAL
    // ===================================================
    //  RVFI trace (riscv-formal)
    //  An instruction is reported when it leaves WB. An instruction
    //  that raises an exception retires with rvfi_trap set and no
    //  register or memory side effects; the first instruction of the
    //  trap handler carries rvfi_intr.
    // ===================================================
    logic [6:0]  rv_op;
    logic        rv_uses_rs1, rv_uses_rs2, rv_leave_ex, rv_rd_we, rv_intr_pending;
    logic [31:0] rv_pc_wdata, rv_wlanes;
    logic [3:0]  rv_rmask, rv_wmask;

    assign rv_op = id_ex_instr[6:0];
    always_comb begin
        rv_uses_rs1 = (rv_op == 7'b0110011) || (rv_op == 7'b0010011) || (rv_op == 7'b0000011) ||
                      (rv_op == 7'b0100011) || (rv_op == 7'b1100011) || (rv_op == 7'b1100111) ||
                      (rv_op == 7'b0000111) || (rv_op == 7'b0100111) ||                    // FLW/FSW base
                      ((rv_op == 7'b1110011) && (id_ex_instr[13:12] != 2'b00) && !id_ex_instr[14]) || // CSR reg forms
                      ((rv_op == 7'b1010011) && (id_ex_instr[31:25] == 7'b1101000 ||
                                                 id_ex_instr[31:25] == 7'b1111000));     // FCVT.S.W[U], FMV.W.X
        rv_uses_rs2 = (rv_op == 7'b0110011) || (rv_op == 7'b0100011) || (rv_op == 7'b1100011);
        rv_rmask = 4'b0000;
        rv_wmask = 4'b0000;
        rv_wlanes = 32'b0;
        if (id_ex_mem_read && !ex_exc_taken)
            case (id_ex_funct3[1:0])
                2'b00:   rv_rmask = 4'b0001 << ex_alu_result_raw[1:0];
                2'b01:   rv_rmask = 4'b0011 << ex_alu_result_raw[1:0];
                default: rv_rmask = 4'b1111;
            endcase
        if (id_ex_mem_write && !ex_exc_taken)
            case (id_ex_funct3[1:0])
                2'b00:   begin rv_wmask = 4'b0001 << ex_alu_result_raw[1:0]; rv_wlanes = {4{dmem_wdata[7:0]}};  end
                2'b01:   begin rv_wmask = 4'b0011 << ex_alu_result_raw[1:0]; rv_wlanes = {2{dmem_wdata[15:0]}}; end
                default: begin rv_wmask = 4'b1111;                          rv_wlanes = dmem_wdata;          end
            endcase
    end
    assign rv_pc_wdata = ex_exc_taken  ? trap_pc[31:0] :
                         id_ex_mret_r  ? ex_csr_mepc[31:0] :
                         id_ex_sret_r  ? ex_csr_sepc[31:0] :
                         control_taken ? control_target[31:0] : (id_ex_pc[31:0] + 32'd4);
    assign rv_leave_ex = !muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall;
    assign rv_rd_we    = id_ex_reg_write && (id_ex_rd != 5'd0) && !ex_exc_taken;

    // EX -> MEM
    logic        rvx_valid, rvx_trap, rvx_intr, rvx_rd_we;
    logic [31:0] rvx_insn, rvx_pc_r, rvx_pc_w, rvx_rs1, rvx_rs2, rvx_maddr, rvx_mwdata;
    logic [4:0]  rvx_rs1a, rvx_rs2a, rvx_rd;
    logic [3:0]  rvx_rmask, rvx_wmask;
    logic [1:0]  rvx_mode;
    // MEM -> WB
    logic        rvw_valid, rvw_trap, rvw_intr, rvw_rd_we;
    logic [31:0] rvw_insn, rvw_pc_r, rvw_pc_w, rvw_rs1, rvw_rs2, rvw_maddr, rvw_mwdata, rvw_mrdata;
    logic [4:0]  rvw_rs1a, rvw_rs2a, rvw_rd;
    logic [3:0]  rvw_rmask, rvw_wmask;
    logic [1:0]  rvw_mode;
    logic [63:0] rv_order;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvx_valid <= 1'b0; rvw_valid <= 1'b0; rv_order <= 64'd0; rv_intr_pending <= 1'b0;
        end else begin
            if (rv_leave_ex && id_ex_valid) begin
                rv_intr_pending <= trap_taken;          // the handler's first instruction is next
            end else if (trap_taken)
                rv_intr_pending <= 1'b1;

            rvx_valid <= rv_leave_ex && id_ex_valid;
            if (rv_leave_ex && id_ex_valid) begin
                rvx_trap   <= ex_exc_taken;
                rvx_intr   <= rv_intr_pending;
                rvx_insn   <= id_ex_instr;
                rvx_pc_r   <= id_ex_pc[31:0];
                rvx_pc_w   <= rv_pc_wdata;
                rvx_rs1a   <= rv_uses_rs1 ? id_ex_rs1_addr : 5'd0;
                rvx_rs2a   <= rv_uses_rs2 ? id_ex_rs2_addr : 5'd0;
                rvx_rs1    <= (rv_uses_rs1 && id_ex_rs1_addr != 5'd0) ? ex_fwd_a[31:0] : 32'd0;
                rvx_rs2    <= (rv_uses_rs2 && id_ex_rs2_addr != 5'd0) ? ex_fwd_b[31:0] : 32'd0;
                rvx_rd_we  <= rv_rd_we;
                rvx_rd     <= id_ex_rd;
                rvx_maddr  <= {ex_alu_result_raw[31:2], 2'b00};
                rvx_rmask  <= rv_rmask;
                rvx_wmask  <= rv_wmask;
                rvx_mwdata <= rv_wlanes;
                rvx_mode   <= current_priv;
            end

            rvw_valid <= rvx_valid;
            if (rvx_valid) begin
                rvw_trap <= rvx_trap; rvw_intr <= rvx_intr; rvw_insn <= rvx_insn;
                rvw_pc_r <= rvx_pc_r; rvw_pc_w <= rvx_pc_w;
                rvw_rs1a <= rvx_rs1a; rvw_rs2a <= rvx_rs2a; rvw_rs1 <= rvx_rs1; rvw_rs2 <= rvx_rs2;
                rvw_rd_we <= rvx_rd_we; rvw_rd <= rvx_rd;
                rvw_maddr <= rvx_maddr; rvw_rmask <= rvx_rmask; rvw_wmask <= rvx_wmask;
                rvw_mwdata <= rvx_mwdata; rvw_mrdata <= dmem_rdata; rvw_mode <= rvx_mode;
            end
            if (rvw_valid) rv_order <= rv_order + 64'd1;
        end
    end

    assign rvfi_valid     = rvw_valid;
    assign rvfi_order     = rv_order;
    assign rvfi_insn      = rvw_insn;
    assign rvfi_trap      = rvw_trap;
    assign rvfi_halt      = 1'b0;
    assign rvfi_intr      = rvw_intr;
    assign rvfi_mode      = rvw_mode;
    assign rvfi_ixl       = 2'd1;
    assign rvfi_rs1_addr  = rvw_rs1a;
    assign rvfi_rs2_addr  = rvw_rs2a;
    assign rvfi_rs1_rdata = rvw_rs1;
    assign rvfi_rs2_rdata = rvw_rs2;
    assign rvfi_rd_addr   = rvw_rd_we ? rvw_rd : 5'd0;
    assign rvfi_rd_wdata  = rvw_rd_we ? wb_wr_data[31:0] : 32'd0;
    assign rvfi_pc_rdata  = rvw_pc_r;
    assign rvfi_pc_wdata  = rvw_pc_w;
    assign rvfi_mem_addr  = rvw_maddr;
    assign rvfi_mem_rmask = rvw_rmask;
    assign rvfi_mem_wmask = rvw_wmask;
    assign rvfi_mem_rdata = rvw_mrdata;
    assign rvfi_mem_wdata = rvw_mwdata;
`endif

endmodule
