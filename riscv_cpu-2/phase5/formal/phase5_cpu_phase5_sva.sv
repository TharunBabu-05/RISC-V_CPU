// ============================================================
//  phase5_cpu_phase5_sva.sv  -  Phase 5 formal assertions
// ============================================================
`timescale 1ns/1ps

module phase5_cpu_phase5_sva #(
    parameter int XLEN = 32
) (
    input  logic            clk,
    input  logic            rst_n,

    input  logic            pc_write,
    input  logic            if_id_write,
    input  logic            control_mux,
    input  logic            flush_ex,
    input  logic            flush_if_id,
    input  logic            flush_ex_mem,
    input  logic            hazard_pc_write,
    input  logic            hazard_if_id_write,
    input  logic            hazard_control_mux,
    input  logic            muldiv_stall,
    input  logic            fpu_stall,
    input  logic            vec_stall,
    input  logic            mem_stall,
    input  logic            mmu_stall,

    input  logic            id_ex_mem_read,
    input  logic [4:0]      id_ex_rd,
    input  logic [4:0]      hazard_rs1,
    input  logic [4:0]      hazard_rs2,
    input  logic [4:0]      id_ex_rs1_addr,
    input  logic [4:0]      id_ex_rs2_addr,

    input  logic [XLEN-1:0] if_id_pc,
    input  logic [31:0]     if_id_instr,
    input  logic            id_ex_reg_write,
    input  logic            id_ex_mem_write,
    input  logic            id_ex_branch,
    input  logic            id_ex_jump,
    input  logic            id_ex_csr_en,
    input  logic [2:0]      id_ex_csr_op,
    input  logic            id_ex_mret_r,
    input  logic            id_ex_sret_r,
    input  logic            ex_mem_reg_write,
    input  logic            ex_mem_mem_read,
    input  logic            ex_mem_mem_write,
    input  logic [4:0]      ex_mem_rd,
    input  logic            wb_reg_write,
    input  logic [4:0]      wb_rd_addr,
    input  logic [1:0]      fwd_a,
    input  logic [1:0]      fwd_b,

    input  logic            ex_csr_write,
    input  logic [XLEN-1:0] ex_csr_src,
    input  logic [XLEN-1:0] ex_csr_mepc,
    input  logic [XLEN-1:0] ex_csr_sepc,
    input  logic [XLEN-1:0] pc_next,
    input  logic            trap_taken,
    input  logic [XLEN-1:0] trap_pc,
    input  logic [XLEN-1:0] trap_mepc,
    input  logic [XLEN-1:0] exc_pc
);

    logic past_valid;

    function automatic logic load_use_hazard(
        input logic        mem_read,
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [4:0]  rs2
    );
        begin
            load_use_hazard = mem_read && (rd != 5'b0) && ((rd == rs1) || (rd == rs2));
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            past_valid <= 1'b0;
        end else begin
            past_valid <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (past_valid) begin
            assert(pc_write == (hazard_pc_write && !muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall));
            assert(if_id_write == (hazard_if_id_write && !muldiv_stall && !fpu_stall && !vec_stall && !mem_stall && !mmu_stall));
            assert(control_mux == hazard_control_mux);
            assert(hazard_pc_write == !load_use_hazard(id_ex_mem_read, id_ex_rd, hazard_rs1, hazard_rs2));
            assert(hazard_if_id_write == !load_use_hazard(id_ex_mem_read, id_ex_rd, hazard_rs1, hazard_rs2));
            assert(hazard_control_mux == load_use_hazard(id_ex_mem_read, id_ex_rd, hazard_rs1, hazard_rs2));

            if ($past(rst_n) && !$past(if_id_write) && !$past(flush_ex)) begin
                assert(if_id_pc == $past(if_id_pc));
                assert(if_id_instr == $past(if_id_instr));
            end

            if ($past(flush_ex)) begin
                assert(if_id_instr == 32'h0000_0013);
                assert(id_ex_reg_write == 1'b0);
                assert(id_ex_mem_write == 1'b0);
                assert(id_ex_mem_read == 1'b0);
                assert(id_ex_branch == 1'b0);
                assert(id_ex_jump == 1'b0);
                assert(id_ex_csr_en == 1'b0);
            end

            if ($past(flush_ex_mem)) begin
                assert(ex_mem_reg_write == 1'b0);
                assert(ex_mem_mem_read == 1'b0);
                assert(ex_mem_mem_write == 1'b0);
            end

            if (ex_mem_reg_write && ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs1_addr) begin
                assert(fwd_a == 2'b10);
            end else if (wb_reg_write && wb_rd_addr != 5'd0 && wb_rd_addr == id_ex_rs1_addr) begin
                assert(fwd_a == 2'b01);
            end else begin
                assert(fwd_a == 2'b00);
            end

            if (ex_mem_reg_write && ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs2_addr) begin
                assert(fwd_b == 2'b10);
            end else if (wb_reg_write && wb_rd_addr != 5'd0 && wb_rd_addr == id_ex_rs2_addr) begin
                assert(fwd_b == 2'b01);
            end else begin
                assert(fwd_b == 2'b00);
            end

            if (!id_ex_csr_en) begin
                assert(ex_csr_write == 1'b0);
            end else begin
                case (id_ex_csr_op)
                    3'b001,
                    3'b101: assert(ex_csr_write == 1'b1);
                    3'b010,
                    3'b011,
                    3'b110,
                    3'b111: assert(ex_csr_write == (ex_csr_src != {XLEN{1'b0}}));
                    default: assert(ex_csr_write == 1'b0);
                endcase
            end

            if (trap_taken) begin
                assert(pc_next == trap_pc);
                assert(trap_mepc == exc_pc);
            end

            if (id_ex_mret_r) begin
                assert(pc_next == ex_csr_mepc);
            end

            if (id_ex_sret_r) begin
                assert(pc_next == ex_csr_sepc);
            end
        end
    end

endmodule
