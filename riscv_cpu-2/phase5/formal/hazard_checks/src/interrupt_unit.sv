// ============================================================
//  interrupt_unit.sv  –  Interrupt controller (M-mode only)
//  Handles external interrupts and trap redirection to handler.
//  Integrates with CSR registers (mstatus, mie, mip, mtvec, mepc, mcause)
// ============================================================
`timescale 1ns/1ps

module interrupt_unit #(
    parameter int XLEN = 32
) (
    input  logic        clk,
    input  logic        rst_n,
    
    // From CPU
    input  logic [XLEN-1:0] pc,
    input  logic [XLEN-1:0] next_pc,
    input  logic [31:0] instr,
    input  logic        instr_valid,
    
    // Exception signals
    input  logic        illegal_instr,   // Illegal instruction detected
    input  logic        ecall,            // ECALL instruction
    input  logic        ebreak,           // EBREAK instruction (trap)
    input  logic        page_fault,       // MMU/page fault exception
    input  logic [XLEN-1:0] page_fault_cause,
    
    // External interrupt (async)
    input  logic        ext_interrupt,    // External interrupt request
    
    // CSR interface
    input  logic [XLEN-1:0] mstatus,
    input  logic [XLEN-1:0] mie,
    input  logic [XLEN-1:0] mtvec,
    output logic [XLEN-1:0] mcause_out,
    output logic [XLEN-1:0] mepc_out,
    output logic [XLEN-1:0] mip_out,
    
    // Trap/interrupt outputs
    output logic        trap_taken,
    output logic [XLEN-1:0] trap_pc,
    output logic [1:0]  trap_cause        // 00=none, 01=exception, 10=interrupt
);

    // Machine interrupt pending register simulation
    logic [XLEN-1:0] mip_reg;
    assign mip_out = mip_reg;
    
    // Trap detection
    logic has_exception, has_interrupt;
    logic [XLEN-1:0] exc_cause, int_cause;
    
    // Exception encoding (mcause)
    localparam [XLEN-1:0]
        EXC_ILLEGAL = {{(XLEN-32){1'b0}}, 32'd2},
        EXC_ECALL   = {{(XLEN-32){1'b0}}, 32'd11},
        EXC_EBREAK  = {{(XLEN-32){1'b0}}, 32'd3},
        INT_MEXT    = {1'b1, {(XLEN-1-5){1'b0}}, 5'd11};
    
    // Detect exceptions
    always_comb begin
        has_exception = 1'b0;
        exc_cause = 32'b0;
        
        if (page_fault && instr_valid) begin
            has_exception = 1'b1;
            exc_cause = page_fault_cause;
        end else if (ecall && instr_valid) begin
            has_exception = 1'b1;
            exc_cause = EXC_ECALL;
        end else if (ebreak && instr_valid) begin
            has_exception = 1'b1;
            exc_cause = EXC_EBREAK;
        end else if (illegal_instr && instr_valid) begin
            has_exception = 1'b1;
            exc_cause = EXC_ILLEGAL;
        end
    end
    
    // Detect interrupts (global MIE and individual enable bit)
    logic mstatus_mie;
    assign mstatus_mie = mstatus[3];
    
    always_comb begin
        has_interrupt = 1'b0;
        int_cause = 32'b0;
        
        if (mstatus_mie && ext_interrupt && mie[11]) begin
            has_interrupt = 1'b1;
            int_cause = INT_MEXT;
        end
    end
    
    // Prioritize: exceptions over interrupts
    always_comb begin
        if (has_exception) begin
            trap_taken = 1'b1;
            trap_cause = 2'b01;  // exception
            mcause_out = exc_cause;
            mepc_out = pc;
            trap_pc = (mtvec[1:0] == 2'b00) ? mtvec : (mtvec + (exc_cause << 2));
        end else if (has_interrupt) begin
            trap_taken = 1'b1;
            trap_cause = 2'b10;  // interrupt
            mcause_out = int_cause;
            mepc_out = next_pc;
            trap_pc = (mtvec[1:0] == 2'b00) ? mtvec : (mtvec + ((int_cause & 31'h3F) << 2));
        end else begin
            trap_taken = 1'b0;
            trap_cause = 2'b00;  // no trap
            mcause_out = {XLEN{1'b0}};
            mepc_out = {XLEN{1'b0}};
            trap_pc = {XLEN{1'b0}};
        end
    end
    
    // Update mip based on external interrupt (async)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mip_reg <= {XLEN{1'b0}};
        else
            mip_reg[11] <= ext_interrupt;  // Bit 11 = external interrupt pending
    end

endmodule
