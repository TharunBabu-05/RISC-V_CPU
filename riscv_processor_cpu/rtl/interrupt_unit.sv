// ============================================================
//  interrupt_unit.sv  –  Trap controller (M-mode)
//
//  Selects between synchronous exceptions and the machine external
//  interrupt, and computes the trap target from mtvec:
//    Direct   (MODE=0): every trap enters at BASE
//    Vectored (MODE=1): exceptions enter at BASE,
//                       interrupts at BASE + 4 * cause
// ============================================================
`timescale 1ns/1ps

module interrupt_unit #(
    parameter int XLEN = 32
) (
    input  logic        clk,
    input  logic        rst_n,

    // From CPU
    input  logic [XLEN-1:0] pc,          // PC of the excepting instruction
    input  logic [XLEN-1:0] next_pc,     // resume PC if an interrupt is taken
    input  logic [31:0] instr,           // excepting instruction (illegal-instruction mtval)
    input  logic        instr_valid,     // EX-stage exceptions may be taken this cycle
    input  logic [1:0]  current_priv,

    // Exception signals
    input  logic        illegal_instr,   // Illegal instruction / illegal CSR access
    input  logic        ecall,
    input  logic        ebreak,
    input  logic        misaligned_fetch,  // taken jump/branch to a non-4-byte-aligned target
    input  logic        misaligned_load,
    input  logic        misaligned_store,
    input  logic [XLEN-1:0] misaligned_addr,
    input  logic        page_fault,       // MMU page fault
    input  logic [XLEN-1:0] page_fault_cause,
    input  logic [XLEN-1:0] page_fault_addr,

    // External interrupt
    input  logic        ext_interrupt,    // level-sensitive request
    input  logic        irq_enable,       // pipeline can take an interrupt precisely now

    // CSR interface
    input  logic [XLEN-1:0] mstatus,
    input  logic [XLEN-1:0] mie,
    input  logic [XLEN-1:0] mtvec,
    output logic [XLEN-1:0] mcause_out,
    output logic [XLEN-1:0] mepc_out,
    output logic [XLEN-1:0] mtval_out,
    output logic [XLEN-1:0] mip_out,

    // Trap/interrupt outputs
    output logic        trap_taken,
    output logic [XLEN-1:0] trap_pc,
    output logic [1:0]  trap_cause        // 00=none, 01=exception, 10=interrupt
);

    // Machine interrupt pending (registered copy of the external line)
    logic [XLEN-1:0] mip_reg;
    assign mip_out = mip_reg;

    localparam [XLEN-1:0]
        EXC_INST_MISALIGN  = {{(XLEN-32){1'b0}}, 32'd0},
        EXC_ILLEGAL        = {{(XLEN-32){1'b0}}, 32'd2},
        EXC_EBREAK         = {{(XLEN-32){1'b0}}, 32'd3},
        EXC_LOAD_MISALIGN  = {{(XLEN-32){1'b0}}, 32'd4},
        EXC_STORE_MISALIGN = {{(XLEN-32){1'b0}}, 32'd6},
        EXC_ECALL_U        = {{(XLEN-32){1'b0}}, 32'd8},
        EXC_ECALL_S        = {{(XLEN-32){1'b0}}, 32'd9},
        EXC_ECALL_M        = {{(XLEN-32){1'b0}}, 32'd11},
        INT_MEXT           = {1'b1, {(XLEN-1-5){1'b0}}, 5'd11};

    logic            has_exception, has_interrupt;
    logic [XLEN-1:0] exc_cause, exc_tval;

    always_comb begin
        has_exception = 1'b0;
        exc_cause     = {XLEN{1'b0}};
        exc_tval      = {XLEN{1'b0}};

        if (page_fault) begin
            has_exception = 1'b1;
            exc_cause     = page_fault_cause;
            exc_tval      = page_fault_addr;
        end else if (instr_valid) begin
            if (illegal_instr) begin
                has_exception = 1'b1;
                exc_cause     = EXC_ILLEGAL;
                exc_tval      = {{(XLEN-32){1'b0}}, instr};
            end else if (ecall) begin
                has_exception = 1'b1;
                exc_cause     = (current_priv == 2'b11) ? EXC_ECALL_M :
                                (current_priv == 2'b01) ? EXC_ECALL_S : EXC_ECALL_U;
            end else if (ebreak) begin
                has_exception = 1'b1;
                exc_cause     = EXC_EBREAK;
                exc_tval      = pc;
            end else if (misaligned_fetch) begin
                has_exception = 1'b1;
                exc_cause     = EXC_INST_MISALIGN;
                exc_tval      = misaligned_addr;
            end else if (misaligned_load) begin
                has_exception = 1'b1;
                exc_cause     = EXC_LOAD_MISALIGN;
                exc_tval      = misaligned_addr;
            end else if (misaligned_store) begin
                has_exception = 1'b1;
                exc_cause     = EXC_STORE_MISALIGN;
                exc_tval      = misaligned_addr;
            end
        end
    end

    assign has_interrupt = irq_enable && mstatus[3] && ext_interrupt && mie[11];

    logic [XLEN-1:0] tvec_base;
    assign tvec_base = {mtvec[XLEN-1:2], 2'b00};

    // Exceptions take priority over interrupts
    always_comb begin
        if (has_exception) begin
            trap_taken = 1'b1;
            trap_cause = 2'b01;
            mcause_out = exc_cause;
            mepc_out   = pc;
            mtval_out  = exc_tval;
            trap_pc    = tvec_base;
        end else if (has_interrupt) begin
            trap_taken = 1'b1;
            trap_cause = 2'b10;
            mcause_out = INT_MEXT;
            mepc_out   = next_pc;
            mtval_out  = {XLEN{1'b0}};
            trap_pc    = (mtvec[1:0] == 2'b01) ? (tvec_base + {{(XLEN-6){1'b0}}, 6'd11 << 2}) : tvec_base;
        end else begin
            trap_taken = 1'b0;
            trap_cause = 2'b00;
            mcause_out = {XLEN{1'b0}};
            mepc_out   = {XLEN{1'b0}};
            mtval_out  = {XLEN{1'b0}};
            trap_pc    = {XLEN{1'b0}};
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mip_reg <= {XLEN{1'b0}};
        else
            mip_reg[11] <= ext_interrupt;  // MEIP
    end

endmodule
