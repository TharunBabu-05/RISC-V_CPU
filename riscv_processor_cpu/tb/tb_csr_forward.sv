// ============================================================
//  tb_csr_forward.sv  –  CSR read result forwarding regression
//
//  A CSR instruction's result lives in ex_mem_csr_rdata, not in
//  ex_mem_alu_result. Each case below consumes a CSR read in the
//  very next instruction (EX/MEM forward) or one later (MEM/WB).
// ============================================================
`timescale 1ns/1ps

module tb_csr_forward;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (
        .clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    localparam logic [31:0] NOP = 32'h0000_0013;
    localparam logic [11:0] MSCRATCH = 12'h340;

    function automatic [31:0] itype(input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
        itype = {imm, rs1, f3, rd, op};
    endfunction
    function automatic [31:0] addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        addi = itype(imm, rs1, 3'b000, rd, 7'b0010011);
    endfunction
    function automatic [31:0] csrrw(input [4:0] rd, input [4:0] rs1, input [11:0] csr);
        csrrw = itype(csr, rs1, 3'b001, rd, 7'b1110011);
    endfunction
    function automatic [31:0] csrrs(input [4:0] rd, input [4:0] rs1, input [11:0] csr);
        csrrs = itype(csr, rs1, 3'b010, rd, 7'b1110011);
    endfunction
    function automatic [31:0] add(input [4:0] rd, input [4:0] rs1, input [4:0] rs2);
        add = {7'b0, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction
    function automatic [31:0] sw(input [4:0] rs2, input [4:0] rs1, input [11:0] imm);
        sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function automatic [31:0] lw(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        lw = itype(imm, rs1, 3'b010, rd, 7'b0000011);
    endfunction
    function automatic [31:0] bne(input [4:0] rs1, input [4:0] rs2, input [12:0] imm);
        bne = {imm[12], imm[10:5], rs2, rs1, 3'b001, imm[4:1], imm[11], 7'b1100011};
    endfunction
    function automatic [31:0] slli(input [4:0] rd, input [4:0] rs1, input [4:0] sh);
        slli = itype({7'b0, sh}, rs1, 3'b001, rd, 7'b0010011);
    endfunction

    integer errors = 0;

    task automatic expect_reg(input [4:0] r, input [31:0] exp, input string what);
        if (dut.u_regfile.regs[r] !== exp) begin
            errors++;
            $error("FAIL x%0d %s: got %0d expected %0d", r, what, dut.u_regfile.regs[r], exp);
        end else
            $display("PASS x%0d %s = %0d", r, what, exp);
    endtask

    initial begin
        for (int i = 0; i < 64; i++) dut.u_imem.mem[i] = NOP;

        dut.u_imem.mem[0]  = addi (5'd1, 5'd0, 12'd42);        // x1 = 42
        dut.u_imem.mem[1]  = csrrw(5'd0, 5'd1, MSCRATCH);      // mscratch = 42
        dut.u_imem.mem[2]  = csrrs(5'd2, 5'd0, MSCRATCH);      // x2 = 42
        dut.u_imem.mem[3]  = addi (5'd3, 5'd2, 12'd1);         // x3 = 43   EX/MEM -> rs1
        dut.u_imem.mem[4]  = csrrs(5'd4, 5'd0, MSCRATCH);      // x4 = 42
        dut.u_imem.mem[5]  = add  (5'd5, 5'd0, 5'd4);          // x5 = 42   EX/MEM -> rs2
        dut.u_imem.mem[6]  = csrrs(5'd6, 5'd0, MSCRATCH);      // x6 = 42
        dut.u_imem.mem[7]  = NOP;
        dut.u_imem.mem[8]  = addi (5'd7, 5'd6, 12'd1);         // x7 = 43   MEM/WB -> rs1
        dut.u_imem.mem[9]  = csrrs(5'd8, 5'd0, MSCRATCH);      // x8 = 42
        dut.u_imem.mem[10] = sw   (5'd8, 5'd0, 12'd64);        // mem[64] = 42  store data
        dut.u_imem.mem[11] = lw   (5'd9, 5'd0, 12'd64);        // x9 = 42
        dut.u_imem.mem[12] = csrrs(5'd10, 5'd0, MSCRATCH);     // x10 = 42
        dut.u_imem.mem[13] = bne  (5'd10, 5'd1, 13'd8);        // wrong value -> skips next
        dut.u_imem.mem[14] = addi (5'd11, 5'd0, 12'd1);        // x11 = 1   branch operand
        dut.u_imem.mem[15] = csrrw(5'd12, 5'd0, MSCRATCH);     // x12 = 42, mscratch = 0
        dut.u_imem.mem[16] = slli (5'd13, 5'd12, 5'd1);        // x13 = 84  csrrw swap
        dut.u_imem.mem[17] = csrrs(5'd14, 5'd0, MSCRATCH);     // x14 = 0
        dut.u_imem.mem[18] = addi (5'd15, 5'd14, 12'd5);       // x15 = 5   new CSR value

        #12 rst_n = 1;
        repeat (80) @(posedge clk);

        expect_reg(5'd3,  32'd43, "csrr -> addi (EX/MEM rs1)");
        expect_reg(5'd5,  32'd42, "csrr -> add (EX/MEM rs2)");
        expect_reg(5'd7,  32'd43, "csrr -> nop -> addi (MEM/WB)");
        expect_reg(5'd9,  32'd42, "csrr -> sw store data");
        expect_reg(5'd11, 32'd1,  "csrr -> bne operand");
        expect_reg(5'd13, 32'd84, "csrrw old value -> slli");
        expect_reg(5'd15, 32'd5,  "csrr after csrrw -> addi");

        if (errors == 0)
            $display("All checks passed - CSR forwarding.");
        else
            $display("CSR forwarding FAILED: %0d errors", errors);
        $finish;
    end

endmodule
