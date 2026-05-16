// ============================================================
//  tb_phase6_hazards.sv  – Phase 6: Pipeline Hazard Deep Tests
// ============================================================
`timescale 1ns/1ps
module tb_phase6_hazards;
    logic        clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top #(.IMEM_FILE("")) dut (
        .clk(clk), .rst_n(rst_n), .ext_interrupt(ext_interrupt),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    function automatic logic [31:0] f_addi(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_addi = {imm, rs1, 3'b000, rd, 7'b0010011}; endfunction
    function automatic logic [31:0] f_add(input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2);
        f_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
    function automatic logic [31:0] f_sw(input logic [4:0] rs1, input logic [4:0] rs2, input logic [11:0] imm);
        f_sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}; endfunction
    function automatic logic [31:0] f_lw(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] imm);
        f_lw = {imm, rs1, 3'b010, rd, 7'b0000011}; endfunction
    function automatic logic [31:0] f_beq(input logic [4:0] rs1, input logic [4:0] rs2, input logic [12:0] off);
        logic [12:1] o; o = off[12:1];
        f_beq = {o[12], o[10:5], rs2, rs1, 3'b000, o[4:1], o[11], 7'b1100011}; endfunction
    function automatic logic [31:0] f_csrrw(input logic [4:0] rd, input logic [4:0] rs1, input logic [11:0] csr);
        f_csrrw = {csr, rs1, 3'b001, rd, 7'b1110011}; endfunction
    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        // Setup: store test data
        dut.u_imem.mem[0]  = f_addi(5'd1, 5'd0, 12'd100);
        dut.u_imem.mem[1]  = f_addi(5'd2, 5'd0, 12'd200);
        dut.u_imem.mem[2]  = f_sw  (5'd0, 5'd1, 12'd0);     // mem[0]=100
        dut.u_imem.mem[3]  = f_sw  (5'd0, 5'd2, 12'd4);     // mem[4]=200

        // Test A: Double load-use — both loads then combine
        dut.u_imem.mem[4]  = f_lw  (5'd3, 5'd0, 12'd0);     // x3=100 (stall)
        dut.u_imem.mem[5]  = f_lw  (5'd4, 5'd0, 12'd4);     // x4=200 (stall)
        dut.u_imem.mem[6]  = f_add (5'd5, 5'd3, 5'd4);      // x5=300 (MEM/WB fwd for x3)

        // Test B: Forwarding chain — 4 back-to-back dependent ADDIs
        dut.u_imem.mem[7]  = f_addi(5'd6, 5'd0, 12'd1);     // x6=1
        dut.u_imem.mem[8]  = f_addi(5'd7, 5'd6, 12'd1);     // x7=2 (EX→EX fwd)
        dut.u_imem.mem[9]  = f_addi(5'd8, 5'd7, 12'd1);     // x8=3 (EX→EX fwd)
        dut.u_imem.mem[10] = f_addi(5'd9, 5'd8, 12'd1);     // x9=4 (EX→EX fwd)
        dut.u_imem.mem[11] = f_addi(5'd10,5'd9, 12'd1);     // x10=5 (EX→EX fwd)

        // Test C: Load then independent instr then use (1-cycle stall absorbed)
        dut.u_imem.mem[12] = f_lw  (5'd11, 5'd0, 12'd0);    // x11=100 (stall)
        dut.u_imem.mem[13] = f_addi(5'd12, 5'd0, 12'd50);   // x12=50 (fills stall)
        dut.u_imem.mem[14] = f_add (5'd13, 5'd11, 5'd12);   // x13=150

        // Test D: Branch after load-use (stall+flush interaction)
        dut.u_imem.mem[15] = f_lw  (5'd14, 5'd0, 12'd0);    // x14=100 (stall)
        dut.u_imem.mem[16] = f_addi(5'd15, 5'd0, 12'd100);  // x15=100
        dut.u_imem.mem[17] = f_beq (5'd14, 5'd15, 13'sh00C); // BEQ x14==x15 → +12 → mem[20]
        dut.u_imem.mem[18] = f_addi(5'd16, 5'd0, 12'd99);   // SKIPPED
        dut.u_imem.mem[19] = f_addi(5'd16, 5'd0, 12'd99);   // SKIPPED
        dut.u_imem.mem[20] = f_addi(5'd16, 5'd0, 12'd77);   // x16=77 (branch target)

        // Test E: CSR write then read-back
        dut.u_imem.mem[21] = f_addi(5'd17, 5'd0, 12'd42);
        dut.u_imem.mem[22] = f_csrrw(5'd0, 5'd17, 12'h340); // mscratch=42
        dut.u_imem.mem[23] = f_csrrw(5'd18, 5'd0, 12'h340); // x18=42
        dut.u_imem.mem[24] = NOP;
        dut.u_imem.mem[25] = NOP;
    end

    initial clk = 0;
    always #5 clk = ~clk;
    integer cycle;
    initial begin
        $dumpfile("cpu_phase6_hazards_wave.vcd");
        $dumpvars(0, tb_phase6_hazards);
        rst_n = 0; ext_interrupt = 0; cycle = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(120) @(posedge clk);

        $display("=== Phase 6: Pipeline Hazard Deep Tests ===");

        if (dut.u_regfile.regs[5]  !== 32'd300) $error("FAIL x5 double-load-add: got %0d", dut.u_regfile.regs[5]);
        else $display("PASS x5 double-load-add = %0d", dut.u_regfile.regs[5]);

        if (dut.u_regfile.regs[10] !== 32'd5) $error("FAIL x10 fwd-chain: got %0d", dut.u_regfile.regs[10]);
        else $display("PASS x10 forwarding-chain = %0d", dut.u_regfile.regs[10]);

        if (dut.u_regfile.regs[13] !== 32'd150) $error("FAIL x13 load+add: got %0d", dut.u_regfile.regs[13]);
        else $display("PASS x13 load-stall+add = %0d", dut.u_regfile.regs[13]);

        if (dut.u_regfile.regs[16] !== 32'd77) $error("FAIL x16 branch-after-load: got %0d", dut.u_regfile.regs[16]);
        else $display("PASS x16 branch-after-load-use = %0d", dut.u_regfile.regs[16]);

        if (dut.u_regfile.regs[18] !== 32'd42) $error("FAIL x18 CSR RAW: got %0d", dut.u_regfile.regs[18]);
        else $display("PASS x18 CSR mscratch readback = %0d", dut.u_regfile.regs[18]);

        $display("");
        $display("Phase 6 Hazard Tests: ALL CHECKS DONE");
        $finish;
    end
    always @(posedge clk) if (rst_n) $display("CY%2d | PC=%08h", cycle++, dbg_pc);
endmodule
