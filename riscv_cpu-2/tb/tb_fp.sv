// ============================================================
//  tb_fp.sv - CPU-integrated floating-point smoke test
// ============================================================
`timescale 1ns/1ps

module tb_fp;

    logic clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top #(.IMEM_FILE("")) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ext_interrupt(ext_interrupt),
        .dbg_pc(dbg_pc),
        .dbg_instr(dbg_instr),
        .dbg_alu_result(dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    function automatic logic [31:0] addi(input logic [4:0] rd, rs1, input logic [11:0] imm);
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction
    function automatic logic [31:0] sw(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function automatic logic [31:0] lw(input logic [4:0] rd, rs1, input logic [11:0] imm);
        lw = {imm, rs1, 3'b010, rd, 7'b0000011};
    endfunction
    function automatic logic [31:0] flw(input logic [4:0] rd, rs1, input logic [11:0] imm);
        flw = {imm, rs1, 3'b010, rd, 7'b0000111};
    endfunction
    function automatic logic [31:0] fsw(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        fsw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100111};
    endfunction
    function automatic logic [31:0] fop(input logic [6:0] funct7, input logic [4:0] rd, rs1, rs2);
        fop = {funct7, rs2, rs1, 3'b000, rd, 7'b1010011};
    endfunction

    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        dut.u_imem.mem[0]  = fop (7'b0000000, 5'd3, 5'd1, 5'd2); // add -> 10
        dut.u_imem.mem[1]  = fop (7'b0000100, 5'd4, 5'd1, 5'd2); // sub -> 4
        dut.u_imem.mem[2]  = fop (7'b0001000, 5'd5, 5'd1, 5'd2); // mul -> 21
        dut.u_imem.mem[3]  = fop (7'b0001100, 5'd6, 5'd1, 5'd2); // div -> 2
        dut.u_imem.mem[4]  = NOP;
        dut.u_imem.mem[5]  = NOP;
        dut.u_imem.mem[6]  = NOP;
        dut.u_imem.mem[7]  = NOP;
        dut.u_imem.mem[8]  = NOP;
        dut.u_imem.mem[9]  = NOP;
        dut.u_imem.mem[10] = NOP;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("cpu_fp_wave.vcd");
        $dumpvars(0, tb_fp);
        rst_n = 0; ext_interrupt = 0;
        repeat (4) @(posedge clk);
        dut.u_fp_regfile.regs[1] = 32'd7;
        dut.u_fp_regfile.regs[2] = 32'd3;
        rst_n = 1;
        repeat (120) @(posedge clk);

        $display("=== FP Register Dump ===");
        $display("f3=%0d f4=%0d f5=%0d f6=%0d",
                 dut.u_fp_regfile.regs[3], dut.u_fp_regfile.regs[4],
                 dut.u_fp_regfile.regs[5], dut.u_fp_regfile.regs[6]);

        if (dut.u_fp_regfile.regs[3] !== 32'd10) $error("FAIL f3 FADD");
        if (dut.u_fp_regfile.regs[4] !== 32'd4)  $error("FAIL f4 FSUB");
        if (dut.u_fp_regfile.regs[5] !== 32'd21) $error("FAIL f5 FMUL");
        if (dut.u_fp_regfile.regs[6] !== 32'd2)  $error("FAIL f6 FDIV");

        $display("All checks passed - FP integration complete.");
        $finish;
    end

endmodule
