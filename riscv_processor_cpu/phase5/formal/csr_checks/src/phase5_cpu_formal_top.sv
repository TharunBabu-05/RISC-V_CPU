// ============================================================
//  phase5_cpu_formal_top.sv  -  Formal wrapper for cpu_top
// ============================================================
`timescale 1ns/1ps

module phase5_cpu_formal_top;

    (* gclk *) logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic ext_interrupt = 1'b0;

    logic [31:0] dbg_pc;
    logic [31:0] dbg_instr;
    logic [31:0] dbg_alu_result;
    logic [31:0] dbg_reg_rd_data;

    always_ff @(posedge clk) begin
        rst_n <= 1'b1;
    end

    cpu_top #(
        .IMEM_FILE(""),
        .XLEN(32)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ext_interrupt  (ext_interrupt),
        .dbg_pc         (dbg_pc),
        .dbg_instr      (dbg_instr),
        .dbg_alu_result (dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    bind cpu_top phase5_cpu_phase5_sva #(.XLEN(32)) u_sva (
        .clk             (clk),
        .rst_n           (rst_n),
        .pc_write        (pc_write),
        .if_id_write     (if_id_write),
        .control_mux     (control_mux),
        .flush_ex        (flush_ex),
        .flush_if_id     (flush_if_id),
        .flush_ex_mem    (flush_ex_mem),
        .hazard_pc_write (hazard_pc_write),
        .hazard_if_id_write(hazard_if_id_write),
        .hazard_control_mux(hazard_control_mux),
        .muldiv_stall    (muldiv_stall),
        .fpu_stall       (fpu_stall),
        .vec_stall       (vec_stall),
        .mem_stall       (mem_stall),
        .mmu_stall       (mmu_stall),
        .id_ex_mem_read  (id_ex_mem_read),
        .id_ex_rd        (id_ex_rd),
        .hazard_rs1      (hazard_rs1),
        .hazard_rs2      (hazard_rs2),
        .id_ex_rs1_addr  (id_ex_rs1_addr),
        .id_ex_rs2_addr  (id_ex_rs2_addr),
        .if_id_pc        (if_id_pc),
        .if_id_instr     (if_id_instr),
        .id_ex_reg_write  (id_ex_reg_write),
        .id_ex_mem_write  (id_ex_mem_write),
        .id_ex_branch    (id_ex_branch),
        .id_ex_jump      (id_ex_jump),
        .id_ex_csr_en    (id_ex_csr_en),
        .id_ex_csr_op    (id_ex_csr_op),
        .id_ex_mret_r    (id_ex_mret_r),
        .id_ex_sret_r    (id_ex_sret_r),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_mem_read (ex_mem_mem_read),
        .ex_mem_mem_write(ex_mem_mem_write),
        .ex_mem_rd       (ex_mem_rd),
        .wb_reg_write    (wb_reg_write),
        .wb_rd_addr      (wb_rd_addr),
        .fwd_a           (fwd_a),
        .fwd_b           (fwd_b),
        .ex_csr_write    (ex_csr_write),
        .ex_csr_src      (ex_csr_src),
        .ex_csr_mepc     (ex_csr_mepc),
        .ex_csr_sepc     (ex_csr_sepc),
        .pc_next         (pc_next),
        .trap_taken      (trap_taken),
        .trap_pc         (trap_pc),
        .trap_mepc       (trap_mepc),
        .exc_pc          (exc_pc)
    );

endmodule
