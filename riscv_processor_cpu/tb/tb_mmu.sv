// ============================================================
//  tb_mmu.sv  –  SV32 MMU (TLB + PTW) aggressive tests
// ============================================================
`timescale 1ns/1ps

module tb_mmu;

    logic        clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top #(.IMEM_FILE("")) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ext_interrupt  (ext_interrupt),
        .dbg_pc         (dbg_pc),
        .dbg_instr      (dbg_instr),
        .dbg_alu_result (dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    // Encoding helpers
    function automatic logic [31:0] lui(input logic [4:0] rd, input logic [19:0] imm20);
        lui = {imm20, rd, 7'b0110111};
    endfunction

    function automatic logic [31:0] addi(input logic [4:0] rd, rs1, input logic [11:0] imm);
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic logic [31:0] lw(input logic [4:0] rd, rs1, input logic [11:0] imm);
        lw = {imm, rs1, 3'b010, rd, 7'b0000011};
    endfunction

    function automatic logic [31:0] sw(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] jalr(input logic [4:0] rd, rs1, input logic [11:0] imm);
        jalr = {imm, rs1, 3'b000, rd, 7'b1100111};
    endfunction

    function automatic logic [31:0] csrrw(input logic [4:0] rd, rs1, input logic [11:0] csr);
        csrrw = {csr, rs1, 3'b001, rd, 7'b1110011};
    endfunction

    localparam logic [31:0] NOP = 32'h0000_0013;
    localparam logic [31:0] SATP_SV32 = 32'h8000_0000;

    localparam logic [31:0]
        PTE_CODE   = 32'h0000_00CB, // V,R,X,A,D
        PTE_DATA   = 32'h0000_00C7, // V,R,W,A,D
        PTE_A0     = 32'h0000_0003, // V,R (A=0)
        PTE_D0     = 32'h0000_0047, // V,R,W,A (D=0)
        PTE_R0_X1  = 32'h0000_00C9, // V,X,A,D (R=0)
        PTE_X0     = 32'h0000_00C3; // V,R,A,D (X=0)

    // Clock (10 ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    task automatic clear_imem;
        for (int i = 0; i < 1024; i = i + 1)
            dut.u_imem.mem[i] = NOP;
    endtask

    task automatic clear_dmem;
        for (int i = 0; i < 1024; i = i + 1)
            dut.u_dcache.u_l2.u_dram.u_dmem.mem[i] = 32'b0;
    endtask

    task automatic reset_cpu;
        begin
            rst_n = 0;
            ext_interrupt = 0;
            cycle = 0;
            repeat (4) @(posedge clk);
        end
    endtask

    integer cycle;
    initial begin
        $dumpfile("cpu_mmu_wave.vcd");
        $dumpvars(0, tb_mmu);

        // -------------------------------------------------------
        // Test 1: Successful load via mapped page
        // -------------------------------------------------------
        reset_cpu();
        clear_imem();
        clear_dmem();

        dut.u_dcache.u_l2.u_dram.u_dmem.mem[0]      = PTE_CODE; // VPN1=0x000
        dut.u_dcache.u_l2.u_dram.u_dmem.mem[16'h40] = PTE_DATA; // VPN1=0x040
        dut.u_dcache.u_l2.u_dram.u_dmem.mem[128]    = 32'h1234_5678;

        dut.u_imem.mem[0] = lui  (5'd1, 20'h80000);
        dut.u_imem.mem[1] = csrrw(5'd0, 5'd1, 12'h180);
        dut.u_imem.mem[2] = lui  (5'd2, 20'h10000);
        dut.u_imem.mem[3] = addi (5'd2, 5'd2, 12'h200);
        dut.u_imem.mem[4] = lw   (5'd3, 5'd2, 12'h000);

        rst_n = 1;
        repeat (80) @(posedge clk);

        $display("=== MMU Test 1: Success ===");
        if (dut.u_regfile.regs[3] !== 32'h1234_5678) $error("FAIL test1 x3 (translated load)");
        if (dut.u_csr.mcause !== 32'h0000_0000) $error("FAIL test1 mcause (unexpected fault)");

        // -------------------------------------------------------
        // Test 2: A=0 load fault
        // -------------------------------------------------------
        reset_cpu();
        clear_imem();
        clear_dmem();

        dut.u_dcache.u_l2.u_dram.u_dmem.mem[0]      = PTE_CODE;
        dut.u_dcache.u_l2.u_dram.u_dmem.mem[16'h41] = PTE_A0;   // VPN1=0x041

        dut.u_imem.mem[0] = lui  (5'd1, 20'h80000);
        dut.u_imem.mem[1] = csrrw(5'd0, 5'd1, 12'h180);
        dut.u_imem.mem[2] = lui  (5'd2, 20'h10400);   // 0x1040_0000
        dut.u_imem.mem[3] = lw   (5'd3, 5'd2, 12'h000);

        rst_n = 1;
        repeat (80) @(posedge clk);

        $display("=== MMU Test 2: A=0 Load Fault ===");
        if (dut.u_csr.mcause !== 32'd13) $error("FAIL test2 mcause (expected load page fault)");

        // -------------------------------------------------------
        // Test 3: D=0 store fault
        // -------------------------------------------------------
        reset_cpu();
        clear_imem();
        clear_dmem();

        dut.u_dcache.u_l2.u_dram.u_dmem.mem[0]      = PTE_CODE;
        dut.u_dcache.u_l2.u_dram.u_dmem.mem[16'h42] = PTE_D0;   // VPN1=0x042

        dut.u_imem.mem[0] = lui  (5'd1, 20'h80000);
        dut.u_imem.mem[1] = csrrw(5'd0, 5'd1, 12'h180);
        dut.u_imem.mem[2] = lui  (5'd2, 20'h10800);   // 0x1080_0000
        dut.u_imem.mem[3] = addi (5'd3, 5'd0, 12'd5);
        dut.u_imem.mem[4] = sw   (5'd2, 5'd3, 12'h000);

        rst_n = 1;
        repeat (80) @(posedge clk);

        $display("=== MMU Test 3: D=0 Store Fault ===");
        if (dut.u_csr.mcause !== 32'd15) $error("FAIL test3 mcause (expected store page fault)");
        if (dut.u_dcache.u_l2.u_dram.u_dmem.mem[0] !== PTE_CODE) $error("FAIL test3 data memory (store should not commit)");

        // -------------------------------------------------------
        // Test 4: R=0 load fault
        // -------------------------------------------------------
        reset_cpu();
        clear_imem();
        clear_dmem();

        dut.u_dcache.u_l2.u_dram.u_dmem.mem[0]      = PTE_CODE;
        dut.u_dcache.u_l2.u_dram.u_dmem.mem[16'h43] = PTE_R0_X1; // VPN1=0x043

        dut.u_imem.mem[0] = lui  (5'd1, 20'h80000);
        dut.u_imem.mem[1] = csrrw(5'd0, 5'd1, 12'h180);
        dut.u_imem.mem[2] = lui  (5'd2, 20'h10C00);   // 0x10C0_0000
        dut.u_imem.mem[3] = lw   (5'd3, 5'd2, 12'h000);

        rst_n = 1;
        repeat (80) @(posedge clk);

        $display("=== MMU Test 4: R=0 Load Fault ===");
        if (dut.u_csr.mcause !== 32'd13) $error("FAIL test4 mcause (expected load page fault)");

        // -------------------------------------------------------
        // Test 5: X=0 instruction fault (JALR target)
        // -------------------------------------------------------
        reset_cpu();
        clear_imem();
        clear_dmem();

        dut.u_dcache.u_l2.u_dram.u_dmem.mem[0]      = PTE_CODE;
        dut.u_dcache.u_l2.u_dram.u_dmem.mem[16'h44] = PTE_X0;   // VPN1=0x044

        dut.u_imem.mem[0] = lui  (5'd1, 20'h80000);
        dut.u_imem.mem[1] = csrrw(5'd0, 5'd1, 12'h180);
        dut.u_imem.mem[2] = lui  (5'd2, 20'h11000);   // 0x1100_0000
        dut.u_imem.mem[3] = jalr (5'd0, 5'd2, 12'h000);
        dut.u_imem.mem[4] = NOP;

        rst_n = 1;
        repeat (80) @(posedge clk);

        $display("=== MMU Test 5: X=0 Instruction Fault ===");
        if (dut.u_csr.mcause !== 32'd12) $error("FAIL test5 mcause (expected instruction page fault)");

        $display("MMU SV32 aggressive tests complete.");
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n)
            $display("CY%2d | PC=%08h | INSTR=%08h", cycle++, dbg_pc, dbg_instr);
    end

endmodule
