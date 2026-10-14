`timescale 1ns/1ps

module tb_privilege;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;

    logic csr_write, mret_exec, sret_exec, retire;
    logic [11:0] csr_addr;
    logic [31:0] csr_wdata, csr_rdata;
    logic csr_illegal;
    logic [31:0] mstatus, mie, mtvec, stvec, mepc, sepc, satp, mcause, mideleg, medeleg;
    logic [1:0] current_priv;
    logic [31:0] trap_cause_value, trap_epc, trap_tval, mip;
    logic trap_taken, trap_to_s;
    logic [31:0] trap_pc;
    logic [1:0] trap_kind;
    logic ecall;
    integer errors=0;

    csr_file #(.HAS_FPU(0), .HAS_VEC(0)) csr (
        .clk(clk), .rst_n(rst_n), .csr_write(csr_write), .trap_write(trap_taken),
        .trap_to_s(trap_to_s), .mret_exec(mret_exec), .sret_exec(sret_exec), .retire(retire),
        .csr_addr(csr_addr), .csr_wdata(csr_wdata), .csr_write_attempt(csr_write),
        .trap_mepc(trap_epc), .trap_mcause(trap_cause_value), .trap_mtval(trap_tval),
        .trap_mip(mip), .fflags_set_valid(0), .fflags_set(0), .fs_dirty(0),
        .vcfg_write(0), .vcfg_vl(0), .vcfg_vtype(0), .csr_rdata(csr_rdata),
        .csr_illegal(csr_illegal), .frm_out(), .vl_out(), .vtype_out(), .vstart_out(),
        .mstatus_out(mstatus), .mie_out(mie), .mtvec_out(mtvec), .stvec_out(stvec),
        .mepc_out(mepc), .sepc_out(sepc), .satp_out(satp), .current_priv_out(current_priv),
        .mcause_out(mcause), .mideleg_out(mideleg), .medeleg_out(medeleg),
        .pmpcfg0_out(), .pmpaddr0_out(), .pmpaddr1_out(), .pmpaddr2_out(), .pmpaddr3_out()
    );

    interrupt_unit intr (
        .clk(clk), .rst_n(rst_n), .pc(32'h100), .next_pc(32'h104), .instr(32'h00000073),
        .instr_valid(1'b1), .current_priv(current_priv), .illegal_instr(1'b0),
        .ecall(ecall), .ebreak(1'b0), .misaligned_fetch(1'b0), .misaligned_load(1'b0),
        .misaligned_store(1'b0), .misaligned_addr(0), .page_fault(1'b0),
        .page_fault_cause(0), .page_fault_addr(0), .access_fault(1'b0),
        .access_fault_cause(0), .access_fault_addr(0), .ext_interrupt(1'b0),
        .irq_enable(1'b0), .mstatus(mstatus), .mie(mie), .mip(32'b0), .mtvec(mtvec), .stvec(stvec),
        .mideleg(mideleg), .medeleg(medeleg), .mcause_out(trap_cause_value),
        .mepc_out(trap_epc), .mtval_out(trap_tval), .mip_out(mip),
        .trap_taken(trap_taken), .trap_to_s(trap_to_s), .trap_pc(trap_pc), .trap_cause(trap_kind)
    );

    task write_csr(input [11:0] a, input [31:0] d);
        @(negedge clk); csr_addr=a; csr_wdata=d; csr_write=1;
        @(posedge clk); #1; csr_write=0;
    endtask
    task pulse_mret;
        @(negedge clk); mret_exec=1; @(posedge clk); #1; mret_exec=0;
    endtask
    task pulse_sret;
        @(negedge clk); sret_exec=1; @(posedge clk); #1; sret_exec=0;
    endtask
    task check(input string name, input logic condition);
        if (!condition) begin $error("FAIL %s",name); errors++; end
        else $display("PASS %s",name);
    endtask

    initial begin
        csr_write=0; mret_exec=0; sret_exec=0; retire=0; csr_addr=0; csr_wdata=0; ecall=0;
        #20 rst_n=1;
        write_csr(12'h105, 32'h0000_0200); // stvec
        write_csr(12'h302, 32'h0000_0100); // delegate ECALL from U
        write_csr(12'h300, 32'h0000_0800); // MPP=S
        pulse_mret();
        check("MRET enters S-mode", current_priv == 2'b01);
        pulse_sret();
        check("SRET enters U-mode", current_priv == 2'b00);

        @(negedge clk); ecall=1; #1;
        check("U ECALL delegated", trap_taken && trap_to_s);
        check("delegated target is stvec", trap_pc == 32'h200);
        @(posedge clk); #1; ecall=0;
        check("trap enters S-mode", current_priv == 2'b01);
        check("sepc captures PC", sepc == 32'h100);

        csr_addr=12'h142; #1;
        check("scause records ECALL-U", csr_rdata == 32'd8);
        pulse_sret();
        check("SRET restores U-mode", current_priv == 2'b00);

        if (errors==0) $display("All checks passed - S-mode delegation.");
        else $display("S-mode delegation FAILED: %0d errors",errors);
        $finish;
    end
endmodule
