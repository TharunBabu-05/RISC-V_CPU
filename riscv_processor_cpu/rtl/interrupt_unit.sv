// ============================================================
//  interrupt_unit.sv - Precise M/S-mode trap controller
// ============================================================
`timescale 1ns/1ps

module interrupt_unit #(
    parameter int XLEN = 32
) (
    input  logic            clk,
    input  logic            rst_n,
    input  logic [XLEN-1:0] pc,
    input  logic [XLEN-1:0] next_pc,
    input  logic [31:0]     instr,
    input  logic            instr_valid,
    input  logic [1:0]      current_priv,
    input  logic            illegal_instr,
    input  logic            ecall,
    input  logic            ebreak,
    input  logic            misaligned_fetch,
    input  logic            misaligned_load,
    input  logic            misaligned_store,
    input  logic [XLEN-1:0] misaligned_addr,
    input  logic            page_fault,
    input  logic [XLEN-1:0] page_fault_cause,
    input  logic [XLEN-1:0] page_fault_addr,
    input  logic            access_fault,
    input  logic [XLEN-1:0] access_fault_cause,
    input  logic [XLEN-1:0] access_fault_addr,
    input  logic            ext_interrupt,
    input  logic            irq_enable,
    input  logic [XLEN-1:0] mstatus,
    input  logic [XLEN-1:0] mie,
    input  logic [XLEN-1:0] mip,
    input  logic [XLEN-1:0] mtvec,
    input  logic [XLEN-1:0] stvec,
    input  logic [XLEN-1:0] mideleg,
    input  logic [XLEN-1:0] medeleg,
    output logic [XLEN-1:0] mcause_out,
    output logic [XLEN-1:0] mepc_out,
    output logic [XLEN-1:0] mtval_out,
    output logic [XLEN-1:0] mip_out,
    output logic            trap_taken,
    output logic            trap_to_s,
    output logic [XLEN-1:0] trap_pc,
    output logic [1:0]      trap_cause
);
    localparam logic [1:0] PRIV_M = 2'b11;
    localparam logic [1:0] PRIV_S = 2'b01;

    localparam logic [XLEN-1:0]
        EXC_INST_MISALIGN  = 0,
        EXC_ILLEGAL        = 2,
        EXC_EBREAK         = 3,
        EXC_LOAD_MISALIGN  = 4,
        EXC_STORE_MISALIGN = 6,
        EXC_ECALL_U        = 8,
        EXC_ECALL_S        = 9,
        EXC_ECALL_M        = 11;

    logic [XLEN-1:0] mip_reg;
    logic has_exception, has_interrupt;
    logic [XLEN-1:0] exc_cause, exc_tval;
    logic exception_delegated, interrupt_delegated;
    logic machine_irq_enabled, supervisor_irq_enabled;
    logic [XLEN-1:0] selected_tvec, tvec_base;
    logic [XLEN-1:0] pending_irqs;
    integer exc_index, irq_index;
    logic irq_found;

    assign mip_out = mip_reg;

    always_comb begin
        has_exception = 1'b0;
        exc_cause     = {XLEN{1'b0}};
        exc_tval      = {XLEN{1'b0}};

        if (page_fault) begin
            has_exception = 1'b1;
            exc_cause     = page_fault_cause;
            exc_tval      = page_fault_addr;
        end else if (access_fault) begin
            has_exception = 1'b1;
            exc_cause     = access_fault_cause;
            exc_tval      = access_fault_addr;
        end else if (instr_valid) begin
            if (illegal_instr) begin
                has_exception = 1'b1;
                exc_cause     = EXC_ILLEGAL;
                exc_tval      = {{(XLEN-32){1'b0}}, instr};
            end else if (ecall) begin
                has_exception = 1'b1;
                exc_cause     = (current_priv == PRIV_M) ? EXC_ECALL_M :
                                (current_priv == PRIV_S) ? EXC_ECALL_S : EXC_ECALL_U;
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

    always_comb begin
        exc_index = exc_cause;
        exception_delegated = has_exception && current_priv != PRIV_M &&
                              exc_index < XLEN && medeleg[exc_index];

        // Standard interrupt priority: MEI, MSI, MTI, SEI, SSI, STI. An
        // interrupt delegated to S is masked while execution is already in M.
        pending_irqs = mie & mip;
        if (current_priv == PRIV_M)
            pending_irqs = pending_irqs & ~mideleg;
        irq_found = 1'b1;
        if (pending_irqs[11])      irq_index = 11;
        else if (pending_irqs[3])  irq_index = 3;
        else if (pending_irqs[7])  irq_index = 7;
        else if (pending_irqs[9])  irq_index = 9;
        else if (pending_irqs[1])  irq_index = 1;
        else if (pending_irqs[5])  irq_index = 5;
        else begin
            irq_index = 0;
            irq_found = 1'b0;
        end
        interrupt_delegated = irq_found && current_priv != PRIV_M && mideleg[irq_index];

        // Interrupts are globally enabled in a less-privileged mode. At their
        // target privilege, the corresponding xIE bit gates delivery.
        machine_irq_enabled = (current_priv == PRIV_M) ? mstatus[3] : 1'b1;
        supervisor_irq_enabled = (current_priv == PRIV_S) ? mstatus[1] : 1'b1;
        has_interrupt = irq_enable && irq_found &&
                        (interrupt_delegated ? supervisor_irq_enabled : machine_irq_enabled);
    end

    always_comb begin
        trap_taken  = 1'b0;
        trap_to_s   = 1'b0;
        trap_cause  = 2'b00;
        mcause_out  = {XLEN{1'b0}};
        mepc_out    = {XLEN{1'b0}};
        mtval_out   = {XLEN{1'b0}};
        trap_pc     = {XLEN{1'b0}};
        selected_tvec = mtvec;
        tvec_base   = {XLEN{1'b0}};

        if (has_exception) begin
            trap_taken = 1'b1;
            trap_to_s  = exception_delegated;
            trap_cause = 2'b01;
            mcause_out = exc_cause;
            mepc_out   = pc;
            mtval_out  = exc_tval;
            selected_tvec = exception_delegated ? stvec : mtvec;
            trap_pc = {selected_tvec[XLEN-1:2], 2'b00};
        end else if (has_interrupt) begin
            trap_taken = 1'b1;
            trap_to_s  = interrupt_delegated;
            trap_cause = 2'b10;
            mcause_out = {1'b1, {(XLEN-1){1'b0}}} | irq_index;
            mepc_out   = next_pc;
            selected_tvec = interrupt_delegated ? stvec : mtvec;
            tvec_base = {selected_tvec[XLEN-1:2], 2'b00};
            trap_pc = (selected_tvec[1:0] == 2'b01) ?
                      (tvec_base + (irq_index * 4)) : tvec_base;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mip_reg <= {XLEN{1'b0}};
        else begin
            mip_reg <= {XLEN{1'b0}};
            mip_reg[11] <= ext_interrupt;
        end
    end
endmodule
