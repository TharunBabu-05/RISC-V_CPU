// ============================================================
//  tb_irq_precise.sv  –  Precise external interrupts
//
//  The same program runs four times; each run raises one external
//  interrupt at an awkward pipeline moment:
//    1. EX holds a bubble (right after a JAL flush)
//    2. a DIV is executing (multi-cycle stall)
//    3. a load-use stall is in progress
//    4. a CSR write instruction is in EX
//  Every instruction must execute exactly once and its result must
//  survive. mem[1] (PC 0x4) is a sentinel: re-executing it means the
//  interrupt returned to a bogus mepc.
// ============================================================
`timescale 1ns/1ps

module tb_irq_precise;
    `include "rv_encode.svh"

    logic clk = 0, rst_n = 0, ext_interrupt = 0;
    always #5 clk = ~clk;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (.clk(clk), .rst_n(rst_n), .ext_interrupt(ext_interrupt),
                 .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
                 .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data));

    localparam logic [11:0] MSTATUS = 12'h300, MIE = 12'h304, MTVEC = 12'h305, MSCRATCH = 12'h340;

    integer errors = 0;
    integer scenario;
    logic   fired;

    task automatic load_program;
        for (int i = 0; i < 256; i++) dut.u_imem.mem[i] = RV_NOP;
        dut.u_imem.mem[0]  = rv_addi(5'd6, 5'd0, 12'd0);
        dut.u_imem.mem[1]  = rv_addi(5'd6, 5'd6, 12'd1);       // sentinel @0x4: x6 must end at 1
        dut.u_imem.mem[2]  = rv_addi(5'd7, 5'd0, 12'h200);
        dut.u_imem.mem[3]  = rv_csrw(MTVEC, 5'd7);              // handler @0x200
        dut.u_imem.mem[4]  = rv_addi(5'd7, 5'd0, 12'h800);
        dut.u_imem.mem[5]  = rv_csrw(MIE, 5'd7);                // MEIE
        dut.u_imem.mem[6]  = rv_addi(5'd7, 5'd0, 12'd8);
        dut.u_imem.mem[7]  = rv_csrw(MSTATUS, 5'd7);            // MIE
        dut.u_imem.mem[8]  = rv_addi(5'd8, 5'd0, 12'd100);
        dut.u_imem.mem[9]  = rv_addi(5'd9, 5'd0, 12'd7);
        dut.u_imem.mem[10] = rv_jal (5'd0, 21'd8);              // -> mem[12]; leaves a bubble in EX
        dut.u_imem.mem[11] = rv_addi(5'd3, 5'd0, 12'd99);       // skipped
        dut.u_imem.mem[12] = rv_addi(5'd5, 5'd5, 12'd1);
        dut.u_imem.mem[13] = rv_addi(5'd5, 5'd5, 12'd1);
        dut.u_imem.mem[14] = rv_div (5'd10, 5'd8, 5'd9);        // x10 = 14
        dut.u_imem.mem[15] = rv_addi(5'd5, 5'd5, 12'd1);
        dut.u_imem.mem[16] = rv_sw  (5'd8, 5'd0, 12'h40);
        dut.u_imem.mem[17] = rv_lw  (5'd11, 5'd0, 12'h40);      // x11 = 100
        dut.u_imem.mem[18] = rv_addi(5'd12, 5'd11, 12'd1);      // load-use: x12 = 101
        dut.u_imem.mem[19] = rv_addi(5'd13, 5'd0, 12'd55);
        dut.u_imem.mem[20] = rv_csrw(MSCRATCH, 5'd13);          // mscratch = 55
        dut.u_imem.mem[21] = rv_addi(5'd5, 5'd5, 12'd1);
        dut.u_imem.mem[22] = rv_jal (5'd0, 21'd0);              // spin
        // Handler @0x200 (mem[128]): count and return
        dut.u_imem.mem[128] = rv_addi(5'd31, 5'd31, 12'd1);
        dut.u_imem.mem[129] = RV_MRET;
    endtask

    function automatic logic trigger(input integer s);
        case (s)
            1: trigger = (dut.id_ex_pc == 0) && (dut.id_ex_opcode == 7'b0) && (dut.pc >= 32'h30);
            2: trigger = dut.muldiv_busy;
            3: trigger = dut.control_mux;
            4: trigger = dut.id_ex_csr_en && (dut.id_ex_csr_addr == MSCRATCH);
            default: trigger = 1'b0;
        endcase
    endfunction

    // Raise the interrupt at the chosen moment; drop it once taken.
    always @(negedge clk) begin
        if (rst_n && !fired && !ext_interrupt && trigger(scenario))
            ext_interrupt = 1'b1;
    end
    always @(posedge clk) begin
        if (ext_interrupt && dut.trap_taken) begin
            ext_interrupt <= 1'b0;
            fired <= 1'b1;
        end
    end

    task automatic check(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $error("scenario %0d FAIL %s: got %0d expected %0d", scenario, what, got, exp);
        end
    endtask

    initial begin
        for (scenario = 1; scenario <= 4; scenario++) begin
            rst_n = 0; ext_interrupt = 0; fired = 0;
            load_program();
            repeat (3) @(posedge clk);
            #1 rst_n = 1;
            repeat (250) @(posedge clk);

            check("interrupt taken (x31)",       dut.u_regfile.regs[31], 1);
            check("sentinel @0x4 runs once (x6)", dut.u_regfile.regs[6], 1);
            check("JAL shadow skipped (x3)",      dut.u_regfile.regs[3], 0);
            check("addi x5 count",                dut.u_regfile.regs[5], 4);
            check("DIV result (x10)",             dut.u_regfile.regs[10], 14);
            check("load (x11)",                   dut.u_regfile.regs[11], 100);
            check("load-use (x12)",               dut.u_regfile.regs[12], 101);
            check("CSR write (mscratch)",         dut.u_csr.mscratch, 55);
            $display("scenario %0d done: x5=%0d x6=%0d x10=%0d x12=%0d mscratch=%0d irq=%0d",
                     scenario, dut.u_regfile.regs[5], dut.u_regfile.regs[6], dut.u_regfile.regs[10],
                     dut.u_regfile.regs[12], dut.u_csr.mscratch, dut.u_regfile.regs[31]);
        end

        if (errors == 0) $display("All checks passed - precise interrupts.");
        else             $display("precise interrupts FAILED: %0d errors", errors);
        $finish;
    end
endmodule
