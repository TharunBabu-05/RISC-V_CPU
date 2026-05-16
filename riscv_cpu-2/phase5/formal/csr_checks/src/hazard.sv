// ============================================================
//  hazard.sv  –  Hazard Detection Unit
//  Detects load-use hazards and inserts a stall bubble
// ============================================================
`timescale 1ns/1ps

module hazard_unit (
    // EX stage pipeline register fields
    input  logic       id_ex_mem_read,  // load instruction in EX
    input  logic [4:0] id_ex_rd,        // destination reg in EX

    // ID stage (decoded register addresses)
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,

    // Stall outputs
    output logic pc_write,      // 0 = freeze PC
    output logic if_id_write,   // 0 = freeze IF/ID register
    output logic control_mux    // 1 = insert NOP bubble into ID/EX
);

    logic stall;

    always_comb begin
        stall = id_ex_mem_read &&
                (id_ex_rd != 5'b0) &&
                ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));
    end

    assign pc_write    = ~stall;
    assign if_id_write = ~stall;
    assign control_mux =  stall;

endmodule


// ============================================================
//  forwarding.sv  –  Forwarding Unit
//  Resolves RAW hazards without stalling where possible:
//    EX forwarding  : result from previous instruction
//    MEM forwarding : result from two instructions back
// ============================================================
module forwarding_unit (
    // Source registers in EX stage
    input  logic [4:0] ex_rs1,
    input  logic [4:0] ex_rs2,

    // EX/MEM pipeline register
    input  logic [4:0] ex_mem_rd,
    input  logic       ex_mem_reg_write,

    // MEM/WB pipeline register
    input  logic [4:0] mem_wb_rd,
    input  logic       mem_wb_reg_write,

    // Forwarding MUX selects (2-bit per operand)
    // 00 = regfile, 01 = MEM/WB, 10 = EX/MEM
    output logic [1:0] fwd_a,
    output logic [1:0] fwd_b
);

    // Operand A (rs1)
    always_comb begin
        if (ex_mem_reg_write && ex_mem_rd != 5'b0 && ex_mem_rd == ex_rs1)
            fwd_a = 2'b10;          // EX/MEM forward
        else if (mem_wb_reg_write && mem_wb_rd != 5'b0 && mem_wb_rd == ex_rs1)
            fwd_a = 2'b01;          // MEM/WB forward
        else
            fwd_a = 2'b00;          // no forwarding
    end

    // Operand B (rs2)
    always_comb begin
        if (ex_mem_reg_write && ex_mem_rd != 5'b0 && ex_mem_rd == ex_rs2)
            fwd_b = 2'b10;
        else if (mem_wb_reg_write && mem_wb_rd != 5'b0 && mem_wb_rd == ex_rs2)
            fwd_b = 2'b01;
        else
            fwd_b = 2'b00;
    end

endmodule
