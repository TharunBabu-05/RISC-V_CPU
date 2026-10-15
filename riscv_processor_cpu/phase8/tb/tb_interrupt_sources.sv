`timescale 1ns/1ps

module tb_interrupt_sources;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic ext_interrupt = 1'b0;
    logic timer_interrupt = 1'b0;
    logic software_interrupt = 1'b0;
    logic [31:0] mip_live;
    logic [31:0] mcause_out;
    logic [31:0] mepc_out, mtval_out, trap_pc;
    logic trap_taken, trap_to_s;
    logic [1:0] trap_cause;
    integer errors = 0;

    always #5 clk = ~clk;

    interrupt_unit dut (
        .clk(clk), .rst_n(rst_n), .pc(32'h100), .next_pc(32'h104),
        .instr(32'h00000013), .instr_valid(1'b1), .current_priv(2'b11),
        .illegal_instr(1'b0), .ecall(1'b0), .ebreak(1'b0),
        .misaligned_fetch(1'b0), .misaligned_load(1'b0),
        .misaligned_store(1'b0), .misaligned_addr(32'b0),
        .page_fault(1'b0), .page_fault_cause(32'b0), .page_fault_addr(32'b0),
        .access_fault(1'b0), .access_fault_cause(32'b0), .access_fault_addr(32'b0),
        .ext_interrupt(ext_interrupt), .timer_interrupt(timer_interrupt),
        .software_interrupt(software_interrupt), .irq_enable(1'b1),
        .mstatus(32'h8), .mie(32'h00000888), .mip(mip_live),
        .mtvec(32'h200), .stvec(32'b0), .mideleg(32'b0), .medeleg(32'b0),
        .mcause_out(mcause_out), .mepc_out(mepc_out), .mtval_out(mtval_out),
        .mip_out(mip_live), .trap_taken(trap_taken), .trap_to_s(trap_to_s),
        .trap_pc(trap_pc), .trap_cause(trap_cause)
    );

    task automatic check_irq(input string what, input [31:0] expected);
        begin
            @(posedge clk); #1;
            if (!trap_taken || mcause_out !== expected) begin
                errors = errors + 1;
                $error("FAIL %s: taken=%b cause=%h expected=%h",
                       what, trap_taken, mcause_out, expected);
            end else
                $display("PASS %s cause=%h", what, expected);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        software_interrupt = 1'b1;
        check_irq("machine software interrupt", 32'h80000003);
        software_interrupt = 1'b0;
        @(posedge clk); #1;

        timer_interrupt = 1'b1;
        check_irq("machine timer interrupt", 32'h80000007);
        timer_interrupt = 1'b0;
        @(posedge clk); #1;

        ext_interrupt = 1'b1;
        check_irq("machine external interrupt", 32'h8000000B);
        ext_interrupt = 1'b0;

        if (errors == 0)
            $display("PASS: CPU interrupt source causes");
        else
            $fatal(1, "Interrupt source tests failed: %0d", errors);
        $finish;
    end
endmodule
