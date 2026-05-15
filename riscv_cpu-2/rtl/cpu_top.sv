// ============================================================
//  cpu_top.sv  –  RV32I 5-stage pipelined CPU top-level
//
//  Pipeline registers: IF/ID, ID/EX, EX/MEM, MEM/WB
//  Features:
//    - Full RV32I base integer ISA
//    - Data forwarding (EX→EX, MEM→EX)
//    - Load-use hazard stall
//    - Branch resolution in EX (1-cycle flush on taken branch)
//    - JAL / JALR support
// ============================================================
`timescale 1ns/1ps

module cpu_top #(
    parameter IMEM_FILE = "",
    parameter int XLEN = 32
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ext_interrupt,

    // Debug / testbench observation ports
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_alu_result,
    output logic [31:0] dbg_reg_rd_data
);

    // -------------------------------------------------------
    //  Opcode & opcode constants (used in PC-select logic)
    // -------------------------------------------------------
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

    // PC register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pc <= {XLEN{1'b0}};
        else if (pc_write) pc <= pc_next;
    end

    assign pc_plus4 = pc + {{(XLEN-32){1'b0}}, 32'd4};

    // Instruction cache front-end. The instance name stays u_imem so the
    // existing directed testbenches can still patch instruction storage.
    icache #(.XLEN(XLEN), .IMEM_FILE(IMEM_FILE)) u_imem (
        .clk  (clk),
        .addr (inst_paddr),
        .instr(if_instr)
    );

    branch_predictor #(.XLEN(XLEN)) u_bpred (
        .clk           (clk),
        .rst_n         (rst_n),
        .pc_fetch      (pc),
        .predict_valid (predict_valid),
        .predict_taken (predict_taken),
        .predict_target(predict_target),
        .update        ((id_ex_branch || id_ex_jump) && !muldiv_stall && !fpu_stall && !vec_stall),
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= {XLEN{1'b0}};
            if_id_pred_target <= {XLEN{1'b0}};
            if_id_pred_taken  <= 1'b0;
            if_id_instr <= 32'h0000_0013; // NOP
        end else if (if_id_write) begin
            if (flush_if_id) begin
                if_id_pc    <= {XLEN{1'b0}};
                if_id_pred_target <= {XLEN{1'b0}};
                if_id_pred_taken  <= 1'b0;
                if_id_instr <= 32'h0000_0013;
            end else begin
                if_id_pc    <= pc;
                if_id_pred_target <= predict_target;
                if_id_pred_taken  <= predict_valid && predict_taken;
                if_id_instr <= if_instr;
            end
        end
    end

    // ===================================================
    //  DECODE STAGE
    // ===================================================
    // Register file reads
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [XLEN-1:0] id_rs1_data, id_rs2_data;
    logic [XLEN-1:0] id_imm;
    logic [31:0] id_fp_rs1_data, id_fp_rs2_data, fp_wb_data;
    logic [127:0] id_vec_rs1_data, id_vec_rs2_data, vec_wb_data;
    logic [4:0] fp_wb_rd, vec_wb_rd;
    logic fp_wb_write, vec_wb_write;

    assign id_rs1_addr = if_id_instr[19:15];
    assign id_rs2_addr = if_id_instr[24:20];
    assign id_rd_addr  = if_id_instr[11:7];

    // Writeback data (from WB stage, fed to regfile)
    logic [XLEN-1:0] wb_wr_data;
    logic [4:0]  wb_rd_addr;
    logic        wb_reg_write;

    regfile #(.XLEN(XLEN)) u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs1_data (id_rs1_data),
        .rs2_addr (id_rs2_addr),
        .rs2_data (id_rs2_data),
        .rd_addr  (wb_rd_addr),
        .rd_data  (wb_wr_data),
        .reg_write(wb_reg_write)
    );

    fp_regfile #(.FLEN(32)) u_fp_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs1_data (id_fp_rs1_data),
        .rs2_addr (id_rs2_addr),
        .rs2_data (id_fp_rs2_data),
        .rd_addr  (fp_wb_rd),
        .rd_data  (fp_wb_data),
        .reg_write(fp_wb_write)
    );

    vector_regfile #(.VLEN(128)) u_vec_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs1_data (id_vec_rs1_data),
        .rs2_addr (id_rs2_addr),
        .rs2_data (id_vec_rs2_data),
        .rd_addr  (vec_wb_rd),
        .rd_data  (vec_wb_data),
        .reg_write(vec_wb_write)
    );

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
    logic [2:0]  id_fp_op, id_vec_op;
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

    always_comb begin
        id_fp_en        = (if_id_instr[6:0] == OP_FP);
        id_fp_load      = (if_id_instr[6:0] == OP_LOAD_FP);
        id_fp_store     = (if_id_instr[6:0] == OP_STORE_FP);
        id_fp_reg_write = id_fp_en || id_fp_load;
        id_fp_op        = 3'b000;

        if (id_fp_en) begin
            case (if_id_instr[31:25])
                7'b0000000: id_fp_op = 3'b000; // FADD.S
                7'b0000100: id_fp_op = 3'b001; // FSUB.S
                7'b0001000: id_fp_op = 3'b010; // FMUL.S
                7'b0001100: id_fp_op = 3'b011; // FDIV.S
                default:    id_fp_op = 3'b000;
            endcase
        end

        id_vec_en        = (if_id_instr[6:0] == OP_VECTOR);
        id_vec_reg_write = id_vec_en;
        id_vec_op        = if_id_instr[14:12];

        id_sfence = (if_id_instr[6:0] == OP_SYSTEM) &&
                    (if_id_instr[14:12] == 3'b000) &&
                    (if_id_instr[31:25] == 7'b0001001);
    end

    // Hazard unit
    logic pc_write, if_id_write, control_mux;
    logic hazard_pc_write, hazard_if_id_write, hazard_control_mux;
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

    assign pc_write    = hazard_pc_write    && !muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall;
    assign if_id_write = hazard_if_id_write && !muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall;
    assign control_mux = hazard_control_mux;

    // ===================================================
    //  ID / EX  pipeline register
    // ===================================================
    logic [XLEN-1:0] id_ex_pc, id_ex_rs1, id_ex_rs2, id_ex_imm, id_ex_pred_target;
    logic [31:0] id_ex_fp_rs1, id_ex_fp_rs2;
    logic [127:0] id_ex_vec_rs1, id_ex_vec_rs2;
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
    logic [2:0]  id_ex_fp_op, id_ex_vec_op;
    logic [2:0]  id_ex_muldiv_op;
    logic        id_ex_write;

    assign id_mret = (if_id_instr == 32'h3020_0073);
    assign id_sret = (if_id_instr == 32'h1020_0073);

    assign id_ex_write = ~muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || control_mux || flush_ex) begin
            id_ex_pc         <= {XLEN{1'b0}};
            id_ex_pred_target<= {XLEN{1'b0}};
            id_ex_rs1        <= {XLEN{1'b0}};
            id_ex_rs2        <= {XLEN{1'b0}};
            id_ex_fp_rs1     <= 32'b0;
            id_ex_fp_rs2     <= 32'b0;
            id_ex_vec_rs1    <= 128'b0;
            id_ex_vec_rs2    <= 128'b0;
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
            id_ex_fp_op      <= 3'b0;
            id_ex_vec_en     <= 1'b0;
            id_ex_vec_reg_write <= 1'b0;
            id_ex_vec_op     <= 3'b0;
            id_ex_muldiv_op  <= 3'b0;
        end else if (id_ex_write) begin
            id_ex_pc         <= if_id_pc;
            id_ex_pred_target<= if_id_pred_target;
            id_ex_rs1        <= id_rs1_data;
            id_ex_rs2        <= id_rs2_data;
            id_ex_fp_rs1     <= id_fp_rs1_data;
            id_ex_fp_rs2     <= id_fp_rs2_data;
            id_ex_vec_rs1    <= id_vec_rs1_data;
            id_ex_vec_rs2    <= id_vec_rs2_data;
            id_ex_imm        <= id_imm;
            id_ex_rs1_addr   <= id_rs1_addr;
            id_ex_rs2_addr   <= id_rs2_addr;
            id_ex_rd         <= id_rd_addr;
            id_ex_funct3     <= if_id_instr[14:12];
            id_ex_reg_write  <= id_reg_write;
            id_ex_alu_src    <= id_alu_src;
            id_ex_mem_read   <= id_mem_read || id_fp_load;
            id_ex_mem_write  <= id_mem_write || id_fp_store;
            id_ex_mem_to_reg <= id_mem_to_reg || id_fp_load;
            id_ex_branch     <= id_branch;
            id_ex_jump       <= id_jump;
            id_ex_csr_en     <= id_csr_en;
            id_ex_ecall_r    <= id_ecall;
            id_ex_ebreak_r   <= id_ebreak;
            id_ex_mret_r     <= id_mret;
            id_ex_sret_r     <= id_sret;
            id_ex_sfence     <= id_sfence;
            id_ex_csr_op     <= id_csr_op;
            id_ex_csr_addr   <= id_csr_addr;
            id_ex_csr_zimm   <= id_csr_zimm;
            id_ex_alu_ctrl   <= id_alu_ctrl;
            id_ex_opcode     <= if_id_instr[6:0];
            id_ex_muldiv_en  <= id_muldiv_en;
            id_ex_pred_taken <= if_id_pred_taken;
            id_ex_fp_en      <= id_fp_en;
            id_ex_fp_load    <= id_fp_load;
            id_ex_fp_store   <= id_fp_store;
            id_ex_fp_reg_write <= id_fp_reg_write;
            id_ex_fp_op      <= id_fp_op;
            id_ex_vec_en     <= id_vec_en;
            id_ex_vec_reg_write <= id_vec_reg_write;
            id_ex_vec_op     <= id_vec_op;
            id_ex_muldiv_op  <= id_muldiv_op;
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

    // Forwarding MUXes
    always_comb begin
        case (fwd_a)
            2'b10:   ex_fwd_a = ex_mem_alu_result;   // EX/MEM forward
            2'b01:   ex_fwd_a = wb_wr_data;           // MEM/WB forward
            default: ex_fwd_a = id_ex_rs1;
        endcase

        case (fwd_b)
            2'b10:   ex_fwd_b = ex_mem_alu_result;
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
    assign ex_result = id_ex_muldiv_en ? muldiv_result : ex_alu_result_raw;

    logic fpu_start, fpu_done, fpu_busy;
    logic [31:0] fpu_result;
    assign fpu_start = id_ex_fp_en && !fpu_busy && !flush_ex;

    fpu_unit #(.FLEN(32)) u_fpu (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (flush_ex),
        .start (fpu_start),
        .op    (id_ex_fp_op),
        .a     (id_ex_fp_rs1),
        .b     (id_ex_fp_rs2),
        .busy  (fpu_busy),
        .done  (fpu_done),
        .result(fpu_result)
    );

    assign fpu_stall = id_ex_fp_en && !fpu_done;

    logic vec_start, vec_done, vec_busy;
    logic [127:0] vec_result;
    logic [31:0] vec_vl;
    assign vec_start = id_ex_vec_en && !vec_busy && !flush_ex;
    assign vec_vl = 32'd4;

    vector_unit #(.VLEN(128)) u_vec (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (flush_ex),
        .start (vec_start),
        .op    (id_ex_vec_op),
        .a     (id_ex_vec_rs1),
        .b     (id_ex_vec_rs2),
        .vl    (vec_vl),
        .busy  (vec_busy),
        .done  (vec_done),
        .result(vec_result)
    );

    assign vec_stall = id_ex_vec_en && !vec_done;

    // CSR handling (Zicsr)
    logic [XLEN-1:0] ex_csr_rdata, ex_csr_wdata, ex_csr_src;
    logic [XLEN-1:0] ex_csr_mstatus, ex_csr_mie, ex_csr_mtvec, ex_csr_mepc, ex_csr_sepc, ex_csr_satp;
    logic [1:0]      current_priv;
    logic [XLEN-1:0] trap_pc, trap_mcause, trap_mepc, mip;
    logic        ex_csr_write;
    logic        trap_taken;
    logic        wb_retire;

    assign ex_csr_src = id_ex_csr_op[2] ? id_ex_csr_zimm : ex_fwd_a;

    csr_file #(.XLEN(XLEN)) u_csr (
        .clk         (clk),
        .rst_n       (rst_n),
        .csr_write   (ex_csr_write),
        .trap_write  (trap_taken),
        .mret_exec   (id_ex_mret_r),
        .sret_exec   (id_ex_sret_r),
        .retire      (wb_retire),
        .csr_addr    (id_ex_csr_addr),
        .csr_wdata   (ex_csr_wdata),
        .trap_mepc   (trap_mepc),
        .trap_mcause (trap_mcause),
        .trap_mip    (mip),
        .csr_rdata   (ex_csr_rdata),
        .mstatus_out (ex_csr_mstatus),
        .mie_out     (ex_csr_mie),
        .mtvec_out   (ex_csr_mtvec),
        .mepc_out    (ex_csr_mepc),
        .sepc_out    (ex_csr_sepc),
        .satp_out    (ex_csr_satp),
        .current_priv_out(current_priv),
        .mcause_out  (),
        .mideleg_out (),
        .medeleg_out ()
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
    assign ex_jalr_target = {jalr_sum[31:1], 1'b0};

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
    assign fallthrough_target = id_ex_pc + {{(XLEN-32){1'b0}}, 32'd4};
    assign branch_mispredict = (id_ex_branch || id_ex_jump) &&
                               ((id_ex_pred_taken != control_taken) ||
                                (control_taken && id_ex_pred_taken &&
                                 (id_ex_pred_target != control_target)));

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
            ex_ret_pc = id_ex_pc + {{(XLEN-32){1'b0}}, 32'd4};
    end

    logic page_fault_exception;
    logic [XLEN-1:0] page_fault_cause;
    logic [XLEN-1:0] exc_pc;
    assign page_fault_exception = inst_fault || mem_page_fault;
    assign page_fault_cause = inst_fault ? EXC_INST_PAGE :
                              mem_page_fault_store ? EXC_STORE_PAGE : EXC_LOAD_PAGE;

    always_comb begin
        if (inst_fault)
            exc_pc = pc;
        else if (mem_page_fault)
            exc_pc = ex_mem_pc;
        else
            exc_pc = id_ex_pc;
    end

    interrupt_unit #(.XLEN(XLEN)) u_int (
        .clk             (clk),
        .rst_n           (rst_n),
        .pc              (exc_pc),
        .next_pc         (ex_ret_pc),
        .instr           (32'b0),  // Simplified: no illegal instr detect (future enhancement)
        .instr_valid     (1'b1),   // Assume valid unless async interrupt
        .illegal_instr   (1'b0),   // Not detecting yet
        .ecall           (id_ex_ecall_r),
        .ebreak          (id_ex_ebreak_r),
        .page_fault      (page_fault_exception),
        .page_fault_cause(page_fault_cause),
        .ext_interrupt   (ext_interrupt),
        .mstatus         (ex_csr_mstatus),
        .mie             (ex_csr_mie),
        .mtvec           (ex_csr_mtvec),
        .mcause_out      (trap_mcause),
        .mepc_out        (trap_mepc),
        .mip_out         (mip),
        .trap_taken      (trap_taken),
        .trap_pc         (trap_pc),
        .trap_cause      ()  // Not used in WB, only trap_taken matters
    );
    
    logic flush_ex, flush_ex_mem;
    logic flush_ex_mem_r;  // Delayed by 1 cycle to flush instruction AFTER branch
    
    assign flush_ex = (branch_taken || id_ex_jump || branch_mispredict || trap_taken || id_ex_mret_r || id_ex_sret_r);
    assign flush_if_id = flush_ex;  // Flush IF/ID immediately when branch taken
    
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
        else if (branch_mispredict && !control_taken)
            pc_next = fallthrough_target;
        else if (id_ex_jump && id_ex_opcode == 7'b1100111) // JALR
            pc_next = ex_jalr_target;
        else if (id_ex_jump)                          // JAL
            pc_next = ex_branch_target;
        else if (branch_taken)
            pc_next = ex_branch_target;
        else if (predict_valid && predict_taken)
            pc_next = predict_target;
        else
            pc_next = pc_plus4;
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
        end
    end

    // ===================================================
    //  MEMORY STAGE
    // ===================================================
    logic sfence_exec;
    assign sfence_exec = id_ex_sfence && !flush_ex;

    logic [XLEN-1:0] mem_rd_data;
    logic [XLEN-1:0] data_paddr;
    logic            data_ready, data_fault;
    logic            mem_page_fault, mem_page_fault_store;
    logic            ptw_read;
    logic [XLEN-1:0] ptw_addr;
    logic [31:0]     ptw_rdata;
    logic            data_req;

    assign data_req = ex_mem_mem_read || ex_mem_mem_write;
    assign mem_page_fault = data_req && data_fault;
    assign mem_page_fault_store = ex_mem_mem_write;
    assign mmu_stall = (!inst_ready || (data_req && !data_ready)) && !trap_taken;

    mmu #(.XLEN(XLEN)) u_mmu (
        .clk        (clk),
        .rst_n      (rst_n),
        .satp       (ex_csr_satp),
        .current_priv(current_priv),
        .sfence     (sfence_exec),
        .inst_vaddr (pc),
        .inst_req   (1'b1),
        .inst_paddr (inst_paddr),
        .inst_ready (inst_ready),
        .inst_fault (inst_fault),
        .data_vaddr (ex_mem_alu_result),
        .data_req   (data_req),
        .data_write (ex_mem_mem_write),
        .data_paddr (data_paddr),
        .data_ready (data_ready),
        .data_fault (data_fault),
        .stall      (),
        .ptw_read   (ptw_read),
        .ptw_addr   (ptw_addr),
        .ptw_rdata  (ptw_rdata)
    );

    dcache #(.XLEN(XLEN)) u_dcache (
        .clk      (clk),
        .addr     (data_paddr),
        .wr_data  (ex_mem_fp_store ? {{(XLEN-32){1'b0}}, ex_mem_fp_rs2} : ex_mem_rs2),
        .mem_read (ex_mem_mem_read && data_ready && !data_fault),
        .mem_write(ex_mem_mem_write && data_ready && !data_fault),
        .funct3   (ex_mem_funct3),
        .rd_data  (mem_rd_data),
        .stall    (mem_stall),
        .ptw_read (ptw_read),
        .ptw_addr (ptw_addr),
        .ptw_rdata(ptw_rdata)
    );

    // ===================================================
    //  MEM / WB  pipeline register
    // ===================================================
    logic [XLEN-1:0] mem_wb_alu_result, mem_wb_mem_data, mem_wb_pc_plus4;
    logic [XLEN-1:0] mem_wb_csr_rdata;
    logic [31:0] mem_wb_fp_result;
    logic [127:0] mem_wb_vec_result;
    logic        mem_wb_mem_to_reg, mem_wb_jump, mem_wb_csr_en;
    logic        mem_wb_fp_reg_write, mem_wb_fp_load, mem_wb_vec_reg_write;

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

    assign wb_retire = wb_reg_write && !mem_stall && !mmu_stall;
    assign fp_wb_data = mem_wb_fp_load ? mem_wb_mem_data[31:0] : mem_wb_fp_result;
    assign vec_wb_data = mem_wb_vec_result;

    // ===================================================
    //  Debug outputs
    // ===================================================
    assign dbg_pc          = pc[31:0];
    assign dbg_instr       = if_instr;
    assign dbg_alu_result  = ex_result[31:0];
    assign dbg_reg_rd_data = wb_wr_data[31:0];

endmodule
