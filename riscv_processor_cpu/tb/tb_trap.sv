// ============================================================
//  tb_trap.sv  –  Exceptions, vectored traps and machine CSRs
//
//  mtvec is set to vectored mode (base 0x200). Exceptions must enter
//  at the base; the external interrupt must enter at base + 4*11.
//  The exception handler stores {mcause, mtval, mepc} for every trap
//  to memory at 0x300, then returns to mepc + 4.
// ============================================================
`timescale 1ns/1ps

module tb_trap;
    `include "rv_encode.svh"

    logic clk = 0, rst_n = 0, ext_interrupt = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(ext_interrupt),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    localparam logic [11:0] SSTATUS = 12'h100, MSTATUS = 12'h300, MISA = 12'h301, MIE = 12'h304,
                            MTVEC = 12'h305, MEPC = 12'h341, MCAUSE = 12'h342, MTVAL = 12'h343,
                            CYCLE = 12'hC00, INSTRET = 12'hC02, MHARTID = 12'hF14, BOGUS = 12'h0FF;

    localparam logic [31:0] ILLEGAL_WORD = 32'hFFFF_FFFF;
    logic [31:0] csr_bogus_instr, csr_ro_write_instr;

    `define DMEM dut.u_dcache.u_l2.u_dram.u_dmem.mem
    integer errors = 0;

    task automatic check(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $error("FAIL %s: got %h expected %h", what, got, exp);
        end else
            $display("PASS %s = %h", what, exp);
    endtask

    task automatic check_record(input int n, input string what, input [31:0] cause, input [31:0] tval, input [31:0] epc);
        check({what, " mcause"}, `DMEM[192 + 3*n],     cause);
        check({what, " mtval"},  `DMEM[192 + 3*n + 1], tval);
        check({what, " mepc"},   `DMEM[192 + 3*n + 2], epc);
    endtask

    initial begin
        csr_bogus_instr    = rv_csrr(5'd13, BOGUS);
        csr_ro_write_instr = rv_csrrw(5'd0, 5'd1, MHARTID);

        for (int i = 0; i < 256; i++) dut.u_imem.mem[i] = RV_NOP;
        for (int i = 192; i < 240; i++) `DMEM[i] = 32'h0;

        dut.u_imem.mem[0]  = rv_addi(5'd27, 5'd0, 12'h300);     // record pointer
        dut.u_imem.mem[1]  = rv_addi(5'd7, 5'd0, 12'h201);
        dut.u_imem.mem[2]  = rv_csrw(MTVEC, 5'd7);               // vectored, base 0x200
        dut.u_imem.mem[3]  = RV_ECALL;                           // r0 @0x0C
        dut.u_imem.mem[4]  = ILLEGAL_WORD;                       // r1 @0x10
        dut.u_imem.mem[5]  = rv_lw (5'd10, 5'd0, 12'h102);       // r2 misaligned load
        dut.u_imem.mem[6]  = rv_sw (5'd10, 5'd0, 12'h106);       // r3 misaligned store
        dut.u_imem.mem[7]  = rv_lh (5'd10, 5'd0, 12'h103);       // r4 misaligned half load
        dut.u_imem.mem[8]  = rv_jal(5'd0, 21'd6);                // r5 jump target 0x26
        dut.u_imem.mem[9]  = rv_csrr(5'd11, MISA);
        dut.u_imem.mem[10] = rv_csrr(5'd12, MHARTID);
        dut.u_imem.mem[11] = csr_bogus_instr;                    // r6 unimplemented CSR
        dut.u_imem.mem[12] = rv_csrr(5'd14, CYCLE);
        dut.u_imem.mem[13] = rv_csrr(5'd15, CYCLE);
        dut.u_imem.mem[14] = rv_csrr(5'd16, INSTRET);
        dut.u_imem.mem[15] = csr_ro_write_instr;                 // r7 write to read-only CSR
        dut.u_imem.mem[16] = rv_addi(5'd7, 5'd0, 12'd2);
        dut.u_imem.mem[17] = rv_csrrs(5'd0, 5'd7, MSTATUS);      // set SIE through mstatus
        dut.u_imem.mem[18] = rv_csrr(5'd18, SSTATUS);
        dut.u_imem.mem[19] = rv_csrrc(5'd0, 5'd7, SSTATUS);      // clear SIE through sstatus
        dut.u_imem.mem[20] = rv_csrr(5'd19, MSTATUS);
        dut.u_imem.mem[21] = rv_csrr(5'd21, MTVEC);
        dut.u_imem.mem[22] = rv_addi(5'd7, 5'd0, 12'h800);
        dut.u_imem.mem[23] = rv_csrw(MIE, 5'd7);
        dut.u_imem.mem[24] = rv_addi(5'd7, 5'd0, 12'd8);
        dut.u_imem.mem[25] = rv_csrrs(5'd0, 5'd7, MSTATUS);      // MIE = 1
        dut.u_imem.mem[26] = rv_addi(5'd20, 5'd0, 12'd1);        // tb raises the interrupt here
        dut.u_imem.mem[32] = rv_jal(5'd0, 21'd0);                // spin

        // Exception handler @0x200 (vector base)
        dut.u_imem.mem[128] = rv_csrr(5'd28, MCAUSE);
        dut.u_imem.mem[129] = rv_sw  (5'd28, 5'd27, 12'd0);
        dut.u_imem.mem[130] = rv_csrr(5'd28, MTVAL);
        dut.u_imem.mem[131] = rv_sw  (5'd28, 5'd27, 12'd4);
        dut.u_imem.mem[132] = rv_csrr(5'd28, MEPC);
        dut.u_imem.mem[133] = rv_sw  (5'd28, 5'd27, 12'd8);
        dut.u_imem.mem[134] = rv_addi(5'd27, 5'd27, 12'd12);
        dut.u_imem.mem[135] = rv_addi(5'd28, 5'd28, 12'd4);
        dut.u_imem.mem[136] = rv_csrw(MEPC, 5'd28);
        dut.u_imem.mem[137] = RV_MRET;
        // Machine external interrupt vector @0x22C = base + 4*11
        dut.u_imem.mem[139] = rv_addi(5'd26, 5'd0, 12'd1);
        dut.u_imem.mem[140] = rv_csrr(5'd28, MCAUSE);
        dut.u_imem.mem[141] = rv_sw  (5'd28, 5'd27, 12'd0);
        dut.u_imem.mem[142] = rv_addi(5'd27, 5'd27, 12'd12);
        dut.u_imem.mem[143] = RV_MRET;

        #12 rst_n = 1;
        wait (dut.u_regfile.regs[20] == 1 || $time > 20000);
        @(negedge clk) ext_interrupt = 1;
        wait (dut.trap_taken || $time > 25000);
        @(posedge clk) ext_interrupt <= 0;
        repeat (60) @(posedge clk);

        check_record(0, "ECALL",                32'd11, 32'h0,          32'h0C);
        check_record(1, "illegal instruction",  32'd2,  ILLEGAL_WORD,   32'h10);
        check_record(2, "misaligned LW",        32'd4,  32'h102,        32'h14);
        check_record(3, "misaligned SW",        32'd6,  32'h106,        32'h18);
        check_record(4, "misaligned LH",        32'd4,  32'h103,        32'h1C);
        check_record(5, "misaligned JAL target",32'd0,  32'h26,         32'h20);
        check_record(6, "unimplemented CSR",    32'd2,  csr_bogus_instr,    32'h2C);
        check_record(7, "write read-only CSR",  32'd2,  csr_ro_write_instr, 32'h3C);
        check("vectored interrupt entry (x26)", dut.u_regfile.regs[26], 32'd1);
        check("interrupt record mcause",        `DMEM[192 + 3*8], 32'h8000_000B);
        check("misa = RV32IMF",                 dut.u_regfile.regs[11], 32'h4000_1120);
        check("mhartid",                        dut.u_regfile.regs[12], 32'h0);
        check("cycle counting",                 (dut.u_regfile.regs[14] != 0) && (dut.u_regfile.regs[15] > dut.u_regfile.regs[14]), 1);
        check("instret counting",               dut.u_regfile.regs[16] != 0, 1);
        check("sstatus.SIE mirrors mstatus",    dut.u_regfile.regs[18][1], 1);
        check("mstatus.SIE cleared via sstatus",dut.u_regfile.regs[19][1], 0);
        check("mtvec readback",                 dut.u_regfile.regs[21], 32'h201);

        if (errors == 0) $display("All checks passed - traps and CSRs.");
        else             $display("traps and CSRs FAILED: %0d errors", errors);
        $finish;
    end
endmodule
