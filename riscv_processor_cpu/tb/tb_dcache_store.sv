// ============================================================
//  tb_dcache_store.sv  –  Data cache store-policy regression
//
//  Partial stores (SB/SH) that miss the cache must not allocate a
//  line built from zeros, and must not evict another line that maps
//  to the same index. Full-word stores may allocate. Every case is
//  read back through the cache and checked in backing memory.
//
//  Cache geometry (dcache defaults, XLEN=32): 16 lines x 4 bytes,
//  index = addr[5:2], so 0x100 and 0x140 share index 0.
// ============================================================
`timescale 1ns/1ps

module tb_dcache_store;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    cpu_top dut (
        .clk(clk), .rst_n(rst_n), .ext_interrupt(1'b0),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_alu_result(dbg_alu_result), .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    localparam logic [31:0] NOP = 32'h0000_0013;

    function automatic [31:0] addi(input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction
    function automatic [31:0] store(input [2:0] f3, input [4:0] rs2, input [4:0] rs1, input [11:0] imm);
        store = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
    endfunction
    function automatic [31:0] load(input [2:0] f3, input [4:0] rd, input [4:0] rs1, input [11:0] imm);
        load = {imm, rs1, f3, rd, 7'b0000011};
    endfunction

    localparam [2:0] B = 3'b000, H = 3'b001, W = 3'b010, BU = 3'b100;

    integer errors = 0;

    task automatic expect_val(input string what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            errors++;
            $error("FAIL %s: got %h expected %h", what, got, exp);
        end else
            $display("PASS %s = %h", what, exp);
    endtask

    `define DMEM dut.u_dcache.u_l2.u_dram.u_dmem.mem

    initial begin
        for (int i = 0; i < 64; i++) dut.u_imem.mem[i] = NOP;

        `DMEM[64] = 32'h1122_3300;   // 0x100
        `DMEM[65] = 32'h5566_7788;   // 0x104
        `DMEM[66] = 32'h9999_9999;   // 0x108
        `DMEM[80] = 32'hAABB_CCDD;   // 0x140 (same index as 0x100)

        dut.u_imem.mem[0]  = addi (5'd1, 5'd0, 12'h0AB);         // x1 = 0xAB
        dut.u_imem.mem[1]  = store(B,  5'd1, 5'd0, 12'h100);      // SB miss  -> 0x112233AB
        dut.u_imem.mem[2]  = load (W,  5'd2, 5'd0, 12'h100);      // x2
        dut.u_imem.mem[3]  = store(H,  5'd1, 5'd0, 12'h106);      // SH miss  -> 0x00AB7788
        dut.u_imem.mem[4]  = load (W,  5'd3, 5'd0, 12'h104);      // x3
        dut.u_imem.mem[5]  = load (W,  5'd4, 5'd0, 12'h140);      // x4: 0x140 now cached at index 0
        dut.u_imem.mem[6]  = store(B,  5'd1, 5'd0, 12'h101);      // SB miss on index 0 -> 0x1122ABAB
        dut.u_imem.mem[7]  = load (W,  5'd5, 5'd0, 12'h140);      // x5: 0x140 line must be intact
        dut.u_imem.mem[8]  = load (W,  5'd6, 5'd0, 12'h100);      // x6: brings 0x100 back in
        dut.u_imem.mem[9]  = store(B,  5'd1, 5'd0, 12'h103);      // SB hit   -> 0xAB22ABAB
        dut.u_imem.mem[10] = load (W,  5'd7, 5'd0, 12'h100);      // x7
        dut.u_imem.mem[11] = load (BU, 5'd8, 5'd0, 12'h103);      // x8 = 0xAB
        dut.u_imem.mem[12] = load (B,  5'd9, 5'd0, 12'h103);      // x9 = 0xFFFFFFAB
        dut.u_imem.mem[13] = store(W,  5'd2, 5'd0, 12'h108);      // SW miss (full line) -> 0x112233AB
        dut.u_imem.mem[14] = load (W,  5'd10, 5'd0, 12'h108);     // x10

        #12 rst_n = 1;
        repeat (150) @(posedge clk);

        expect_val("SB miss, then LW (x2)",             dut.u_regfile.regs[2],  32'h1122_33AB);
        expect_val("SH miss upper half, then LW (x3)",  dut.u_regfile.regs[3],  32'h00AB_7788);
        expect_val("LW 0x140 (x4)",                     dut.u_regfile.regs[4],  32'hAABB_CCDD);
        expect_val("SB miss keeps other line (x5)",     dut.u_regfile.regs[5],  32'hAABB_CCDD);
        expect_val("SB miss on conflicting index (x6)", dut.u_regfile.regs[6],  32'h1122_ABAB);
        expect_val("SB hit, then LW (x7)",              dut.u_regfile.regs[7],  32'hAB22_ABAB);
        expect_val("LBU after SB (x8)",                 dut.u_regfile.regs[8],  32'h0000_00AB);
        expect_val("LB after SB (x9)",                  dut.u_regfile.regs[9],  32'hFFFF_FFAB);
        expect_val("SW miss, then LW (x10)",            dut.u_regfile.regs[10], 32'h1122_33AB);
        expect_val("memory word 0x100",                 `DMEM[64], 32'hAB22_ABAB);
        expect_val("memory word 0x104",                 `DMEM[65], 32'h00AB_7788);
        expect_val("memory word 0x108",                 `DMEM[66], 32'h1122_33AB);

        if (errors == 0)
            $display("All checks passed - dcache store policy.");
        else
            $display("dcache store policy FAILED: %0d errors", errors);
        $finish;
    end

endmodule
