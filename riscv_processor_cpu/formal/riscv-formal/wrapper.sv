// ============================================================
//  wrapper.sv  –  riscv-formal wrapper for the FPGA SoC core
//
//  cpu_top_soc (the core that runs on the Arty S7) with fully
//  unconstrained instruction and data memory: every fetched
//  instruction word and every loaded data word is a free variable,
//  so the checks cover arbitrary programs and memory contents.
//  The core reports retired instructions through its RVFI port
//  (compiled in with `define RISCV_FORMAL).
// ============================================================
module rvfi_wrapper (
    input clock,
    input reset,
    `RVFI_OUTPUTS
);
    (* keep *) `rvformal_rand_reg [31:0] imem_rdata;
    (* keep *) `rvformal_rand_reg [31:0] dmem_rdata;

    (* keep *) wire [31:0] imem_addr;
    (* keep *) wire [31:0] dmem_addr;
    (* keep *) wire [31:0] dmem_wdata;
    (* keep *) wire        dmem_rd_en;
    (* keep *) wire        dmem_wr_en;
    (* keep *) wire [2:0]  dmem_funct3;
    wire [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top_soc #(.XLEN(32), .HAS_FPU(1'b0)) uut (
        .clk            (clock),
        .rst_n          (!reset),
        .ext_interrupt  (1'b0),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_rdata     (dmem_rdata),
        .dmem_rd_en     (dmem_rd_en),
        .dmem_wr_en     (dmem_wr_en),
        .dmem_funct3    (dmem_funct3),
        .dbg_pc         (dbg_pc),
        .dbg_instr      (dbg_instr),
        .dbg_alu_result (dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data),
        `RVFI_CONN32
    );
endmodule
