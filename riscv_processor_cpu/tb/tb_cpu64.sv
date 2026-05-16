// ============================================================
//  tb_cpu64.sv  –  RV64I sanity test (XLEN=64)
// ============================================================
`timescale 1ns/1ps

module tb_cpu64;

    // -------------------------------------------------------
    //  DUT signals
    // -------------------------------------------------------
    logic        clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    // -------------------------------------------------------
    //  Instantiate CPU (XLEN=64)
    // -------------------------------------------------------
    cpu_top #(.IMEM_FILE(""), .XLEN(64)) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ext_interrupt  (ext_interrupt),
        .dbg_pc         (dbg_pc),
        .dbg_instr      (dbg_instr),
        .dbg_alu_result (dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    // -------------------------------------------------------
    //  Patch instruction memory with RV64I program
    // -------------------------------------------------------
    function automatic logic [31:0] addi(input logic [4:0] rd, rs1, input logic [11:0] imm);
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction
    function automatic logic [31:0] add(input logic [4:0] rd, rs1, rs2);
        add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction
    function automatic logic [31:0] slli(input logic [4:0] rd, rs1, input logic [5:0] shamt);
        slli = {6'b000000, shamt, rs1, 3'b001, rd, 7'b0010011};
    endfunction
    function automatic logic [31:0] sw(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function automatic logic [31:0] sd(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        sd = {imm[11:5], rs2, rs1, 3'b011, imm[4:0], 7'b0100011};
    endfunction
    function automatic logic [31:0] lw(input logic [4:0] rd, rs1, input logic [11:0] imm);
        lw = {imm, rs1, 3'b010, rd, 7'b0000011};
    endfunction
    function automatic logic [31:0] lwu(input logic [4:0] rd, rs1, input logic [11:0] imm);
        lwu = {imm, rs1, 3'b110, rd, 7'b0000011};
    endfunction
    function automatic logic [31:0] ld(input logic [4:0] rd, rs1, input logic [11:0] imm);
        ld = {imm, rs1, 3'b011, rd, 7'b0000011};
    endfunction

    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        // x1 = -1 (0xFFFF...)
        dut.u_imem.mem[0]  = addi(5'd1, 5'd0, 12'hFFF);
        // Store/load 64-bit
        dut.u_imem.mem[1]  = sd  (5'd0, 5'd1, 12'd0);
        dut.u_imem.mem[2]  = ld  (5'd2, 5'd0, 12'd0);
        // LWU zero-extend
        dut.u_imem.mem[3]  = lwu (5'd3, 5'd0, 12'd0);
        // x4 = 1
        dut.u_imem.mem[4]  = addi(5'd4, 5'd0, 12'd1);
        // x5 = x2 + x4 (expect 0)
        dut.u_imem.mem[5]  = add (5'd5, 5'd2, 5'd4);
        // x6 = 1 << 40
        dut.u_imem.mem[6]  = slli(5'd6, 5'd4, 6'd40);
        // Store/load 32-bit word
        dut.u_imem.mem[7]  = sw  (5'd0, 5'd4, 12'd8);
        dut.u_imem.mem[8]  = lw  (5'd7, 5'd0, 12'd8);
        dut.u_imem.mem[9]  = NOP;
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
        $dumpfile("cpu_rv64_wave.vcd");
        $dumpvars(0, tb_cpu64);

        rst_n = 0; ext_interrupt = 0; cycle = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        repeat (80) @(posedge clk);
        cycle = cycle + 1;

        $display("=== RV64I Register Dump ===");
        $display("x1 = 0x%016h (expected FFFFFFFFFFFFFFFF)", dut.u_regfile.regs[1]);
        $display("x2 = 0x%016h (expected FFFFFFFFFFFFFFFF)", dut.u_regfile.regs[2]);
        $display("x3 = 0x%016h (expected 00000000FFFFFFFF)", dut.u_regfile.regs[3]);
        $display("x4 = 0x%016h (expected 0000000000000001)", dut.u_regfile.regs[4]);
        $display("x5 = 0x%016h (expected 0000000000000000)", dut.u_regfile.regs[5]);
        $display("x6 = 0x%016h (expected 0000010000000000)", dut.u_regfile.regs[6]);
        $display("x7 = 0x%016h (expected 0000000000000001)", dut.u_regfile.regs[7]);

        if (dut.u_regfile.regs[1] !== 64'hFFFF_FFFF_FFFF_FFFF) $error("FAIL x1");
        if (dut.u_regfile.regs[2] !== 64'hFFFF_FFFF_FFFF_FFFF) $error("FAIL x2");
        if (dut.u_regfile.regs[3] !== 64'h0000_0000_FFFF_FFFF) $error("FAIL x3");
        if (dut.u_regfile.regs[4] !== 64'h0000_0000_0000_0001) $error("FAIL x4");
        if (dut.u_regfile.regs[5] !== 64'h0000_0000_0000_0000) $error("FAIL x5");
        if (dut.u_regfile.regs[6] !== 64'h0000_0100_0000_0000) $error("FAIL x6");
        if (dut.u_regfile.regs[7] !== 64'h0000_0000_0000_0001) $error("FAIL x7");

        $display("All checks passed – RV64I simulation complete.");
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
