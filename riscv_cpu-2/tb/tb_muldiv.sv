// ============================================================
//  tb_muldiv.sv  –  Testbench for RV32M mul/div instructions
// ============================================================
`timescale 1ns/1ps

module tb_muldiv;

    // -------------------------------------------------------
    //  DUT signals
    // -------------------------------------------------------
    logic        clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    // -------------------------------------------------------
    //  Instantiate CPU (no file load; patch memory directly)
    // -------------------------------------------------------
    cpu_top #(.IMEM_FILE("")) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ext_interrupt  (ext_interrupt),
        .dbg_pc         (dbg_pc),
        .dbg_instr      (dbg_instr),
        .dbg_alu_result (dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    // -------------------------------------------------------
    //  Patch instruction memory with RV32M program
    // -------------------------------------------------------
    function automatic logic [31:0] addi(input logic [4:0] rd, rs1, input logic [11:0] imm);
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic logic [31:0] r_type_m(
        input logic [2:0] funct3,
        input logic [4:0] rd, rs1, rs2
    );
        r_type_m = {7'b0000001, rs2, rs1, funct3, rd, 7'b0110011};
    endfunction

    function automatic logic [31:0] mul(input logic [4:0] rd, rs1, rs2);
        mul = r_type_m(3'b000, rd, rs1, rs2);
    endfunction
    function automatic logic [31:0] mulh(input logic [4:0] rd, rs1, rs2);
        mulh = r_type_m(3'b001, rd, rs1, rs2);
    endfunction
    function automatic logic [31:0] mulhu(input logic [4:0] rd, rs1, rs2);
        mulhu = r_type_m(3'b011, rd, rs1, rs2);
    endfunction
    function automatic logic [31:0] div_f(input logic [4:0] rd, rs1, rs2);
        div_f = r_type_m(3'b100, rd, rs1, rs2);
    endfunction
    function automatic logic [31:0] divu(input logic [4:0] rd, rs1, rs2);
        divu = r_type_m(3'b101, rd, rs1, rs2);
    endfunction
    function automatic logic [31:0] rem(input logic [4:0] rd, rs1, rs2);
        rem = r_type_m(3'b110, rd, rs1, rs2);
    endfunction
    function automatic logic [31:0] remu(input logic [4:0] rd, rs1, rs2);
        remu = r_type_m(3'b111, rd, rs1, rs2);
    endfunction

    // nop = addi x0, x0, 0
    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        // x1 = 7, x2 = 3
        dut.u_imem.mem[0]  = addi(5'd1, 5'd0, 12'd7);
        dut.u_imem.mem[1]  = addi(5'd2, 5'd0, 12'd3);
        // MUL/DIV/REM
        dut.u_imem.mem[2]  = mul (5'd3, 5'd1, 5'd2);      // x3 = 21
        dut.u_imem.mem[3]  = div_f(5'd4, 5'd1, 5'd2);      // x4 = 2
        dut.u_imem.mem[4]  = rem (5'd5, 5'd1, 5'd2);      // x5 = 1
        // x6 = -3
        dut.u_imem.mem[5]  = addi(5'd6, 5'd0, 12'hFFD);
        // High mul variants
        dut.u_imem.mem[6]  = mulh (5'd7, 5'd1, 5'd6);     // x7 = 0xFFFFFFFF
        dut.u_imem.mem[7]  = mulhu(5'd8, 5'd1, 5'd6);     // x8 = 0x00000006
        // Unsigned divide/remainder
        dut.u_imem.mem[8]  = divu(5'd9, 5'd1, 5'd6);      // x9 = 0
        dut.u_imem.mem[9]  = remu(5'd10,5'd1, 5'd6);      // x10 = 7
        // Spin
        dut.u_imem.mem[10] = NOP;
        dut.u_imem.mem[11] = NOP;
    end

    // -------------------------------------------------------
    //  Clock  (10 ns period)
    // -------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    //  Stimulus and checking
    // -------------------------------------------------------
    integer cycle;
    initial begin
        $dumpfile("cpu_muldiv_wave.vcd");
        $dumpvars(0, tb_muldiv);

        // Reset
        rst_n = 0; ext_interrupt = 0; cycle = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Run long enough for mul/div stalls to finish
        repeat (120) @(posedge clk);
        cycle = cycle + 1;

        $display("=== RV32M Register Dump ===");
        $display("x1  = %0d  (expected 7)", dut.u_regfile.regs[1]);
        $display("x2  = %0d  (expected 3)", dut.u_regfile.regs[2]);
        $display("x3  = %0d  (expected 21)", dut.u_regfile.regs[3]);
        $display("x4  = %0d  (expected 2)", dut.u_regfile.regs[4]);
        $display("x5  = %0d  (expected 1)", dut.u_regfile.regs[5]);
        $display("x6  = 0x%08h (expected 0xFFFFFFFD)", dut.u_regfile.regs[6]);
        $display("x7  = 0x%08h (expected 0xFFFFFFFF)", dut.u_regfile.regs[7]);
        $display("x8  = 0x%08h (expected 0x00000006)", dut.u_regfile.regs[8]);
        $display("x9  = %0d  (expected 0)", dut.u_regfile.regs[9]);
        $display("x10 = %0d  (expected 7)", dut.u_regfile.regs[10]);

        if (dut.u_regfile.regs[1]  !== 32'd7)  $error("FAIL x1");
        if (dut.u_regfile.regs[2]  !== 32'd3)  $error("FAIL x2");
        if (dut.u_regfile.regs[3]  !== 32'd21) $error("FAIL x3 (MUL)");
        if (dut.u_regfile.regs[4]  !== 32'd2)  $error("FAIL x4 (DIV)");
        if (dut.u_regfile.regs[5]  !== 32'd1)  $error("FAIL x5 (REM)");
        if (dut.u_regfile.regs[6]  !== 32'hFFFF_FFFD) $error("FAIL x6 (ADDI -3)");
        if (dut.u_regfile.regs[7]  !== 32'hFFFF_FFFF) $error("FAIL x7 (MULH)");
        if (dut.u_regfile.regs[8]  !== 32'h0000_0006) $error("FAIL x8 (MULHU)");
        if (dut.u_regfile.regs[9]  !== 32'd0) $error("FAIL x9 (DIVU)");
        if (dut.u_regfile.regs[10] !== 32'd7) $error("FAIL x10 (REMU)");

        $display("All checks passed – RV32M simulation complete.");
        $finish;
    end

    // -------------------------------------------------------
    //  Cycle counter display
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n)
            $display("CY%2d | PC=%08h | INSTR=%08h", cycle++, dbg_pc, dbg_instr);
    end

endmodule
