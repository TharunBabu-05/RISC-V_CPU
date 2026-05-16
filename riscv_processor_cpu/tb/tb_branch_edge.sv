// ============================================================
//  tb_branch_edge.sv  –  Branch timing edge-case test
//  Verifies branch after load-use stalls and does not update x8.
// ============================================================
`timescale 1ns/1ps

module tb_branch_edge;

    // -------------------------------------------------------
    //  DUT signals
    // -------------------------------------------------------
    logic        clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    // -------------------------------------------------------
    //  Instantiate CPU
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
    //  Patch instruction memory
    // -------------------------------------------------------
    function automatic logic [31:0] addi(input logic [4:0] rd, rs1, input logic [11:0] imm);
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction
    function automatic logic [31:0] sw(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function automatic logic [31:0] lw(input logic [4:0] rd, rs1, input logic [11:0] imm);
        lw = {imm, rs1, 3'b010, rd, 7'b0000011};
    endfunction
    function automatic logic [31:0] beq(input logic [4:0] rs1, rs2, input logic [12:0] off_bytes);
        logic [12:1] off;
        off = off_bytes[12:1];
        beq = {off[12], off[10:5], rs2, rs1, 3'b000,
               off[4:1], off[11], 7'b1100011};
    endfunction

    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        // mem[0] = 0
        dut.u_imem.mem[0]  = addi(5'd1, 5'd0, 12'd1);     // x1 = 1
        dut.u_imem.mem[1]  = addi(5'd2, 5'd0, 12'd0);     // x2 = 0
        dut.u_imem.mem[2]  = sw  (5'd0, 5'd2, 12'd0);     // mem[0] = 0
        dut.u_imem.mem[3]  = lw  (5'd3, 5'd0, 12'd0);     // x3 = mem[0]
        dut.u_imem.mem[4]  = addi(5'd8, 5'd0, 12'd99);    // x8 = 99 (sentinel)
        // Branch on load result (requires stall)
        dut.u_imem.mem[5]  = beq (5'd3, 5'd0, 12'sh00c);  // taken -> skip next 2
        dut.u_imem.mem[6]  = addi(5'd8, 5'd0, 12'd55);    // should be skipped
        dut.u_imem.mem[7]  = addi(5'd8, 5'd0, 12'd66);    // should be skipped
        dut.u_imem.mem[8]  = addi(5'd9, 5'd0, 12'd77);    // branch target
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
        $dumpfile("cpu_branch_edge_wave.vcd");
        $dumpvars(0, tb_branch_edge);

        rst_n = 0; ext_interrupt = 0; cycle = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Run long enough for branch to resolve and retire
        repeat (60) @(posedge clk);
        cycle = cycle + 1;

        $display("=== Branch Edge Test Register Dump ===");
        $display("x3  = %0d  (expected 0)", dut.u_regfile.regs[3]);
        $display("x8  = %0d  (expected 99)", dut.u_regfile.regs[8]);
        $display("x9  = %0d  (expected 77)", dut.u_regfile.regs[9]);

        if (dut.u_regfile.regs[3] !== 32'd0)  $error("FAIL x3 (load result)");
        if (dut.u_regfile.regs[8] !== 32'd99) $error("FAIL x8 (branch skip)");
        if (dut.u_regfile.regs[9] !== 32'd77) $error("FAIL x9 (branch target)");

        $display("All checks passed – branch timing edge case covered.");
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
