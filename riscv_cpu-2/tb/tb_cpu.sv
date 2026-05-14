// ============================================================
//  tb_cpu.sv  –  Testbench for RV32I CPU
//  Loads a small test program, runs it, and checks results.
//
//  Test program (hand-assembled RV32I):
//    1. addi x1, x0, 10      # x1 = 10
//    2. addi x2, x0, 20      # x2 = 20
//    3. add  x3, x1, x2      # x3 = 30  (data hazard → forwarded)
//    4. sw   x3, 0(x0)       # mem[0] = 30
//    5. lw   x4, 0(x0)       # x4 = 30  (load-use hazard → stall)
//    6. sub  x5, x4, x1      # x5 = 20
//    7. slt  x6, x1, x2      # x6 = 1  (10 < 20)
//    8. beq  x1, x1, +8      # branch forward 2 instr (always taken)
//    9. addi x7, x0, 99      # SKIPPED
//   10. addi x8, x0, 99      # SKIPPED
//   11. addi x9, x0, 42      # x9 = 42  (branch target)
//   12. jal  x10, +8         # x10 = PC+4, jump 2 fwd
//   13. addi x11, x0, 99     # SKIPPED
//   14. addi x12, x0, 77     # x12 = 77  (JAL target)
//   15. nop  (loop forever)
// ============================================================
`timescale 1ns/1ps

module tb_cpu;

    // -------------------------------------------------------
    //  DUT signals
    // -------------------------------------------------------
    logic        clk, rst_n, ext_interrupt;
    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;

    // -------------------------------------------------------
    //  Instantiate CPU (no file load; patch memory directly)
    // -------------------------------------------------------
    cpu_top #(.IMEM_FILE("")) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .ext_interrupt (ext_interrupt),
        .dbg_pc        (dbg_pc),
        .dbg_instr     (dbg_instr),
        .dbg_alu_result(dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    // -------------------------------------------------------
    //  Patch instruction memory with hand-assembled program
    // -------------------------------------------------------
    // RV32I encoding helpers (immediate formats)
    // addi rd, rs1, imm  → opcode=0010011, funct3=000
    function automatic logic [31:0] addi(input logic [4:0] rd, rs1, input logic [11:0] imm);
        addi = {imm, rs1, 3'b000, rd, 7'b0010011};
    endfunction
    // add rd, rs1, rs2   → opcode=0110011, funct3=000, funct7=0
    function automatic logic [31:0] add(input logic [4:0] rd, rs1, rs2);
        add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction
    // sub rd, rs1, rs2
    function automatic logic [31:0] sub(input logic [4:0] rd, rs1, rs2);
        sub = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction
    // slt rd, rs1, rs2
    function automatic logic [31:0] slt_f(input logic [4:0] rd, rs1, rs2);
        slt_f = {7'b0000000, rs2, rs1, 3'b010, rd, 7'b0110011};
    endfunction
    // sw rs2, imm(rs1)   → opcode=0100011, funct3=010
    function automatic logic [31:0] sw(input logic [4:0] rs1, rs2, input logic [11:0] imm);
        sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    // lw rd, imm(rs1)    → opcode=0000011, funct3=010
    function automatic logic [31:0] lw(input logic [4:0] rd, rs1, input logic [11:0] imm);
        lw = {imm, rs1, 3'b010, rd, 7'b0000011};
    endfunction
    // beq rs1, rs2, offset  (byte offset, must be even)
    function automatic logic [31:0] beq(input logic [4:0] rs1, rs2, input logic [12:0] off_bytes);
        logic [12:1] off;
        off = off_bytes[12:1]; // encode in 2-byte units
        beq = {off[12], off[10:5], rs2, rs1, 3'b000,
               off[4:1], off[11], 7'b1100011};
    endfunction
    // jal rd, offset (byte offset, must be even)
    function automatic logic [31:0] jal(input logic [4:0] rd, input logic [20:0] off_bytes);
        logic [20:1] off;
        off = off_bytes[20:1]; // encode in 2-byte units
        jal = {off[20], off[10:1], off[11], off[19:12], rd, 7'b1101111};
    endfunction
    // CSR instructions (Zicsr)
    function automatic logic [31:0] csrrw(input logic [4:0] rd, rs1, input logic [11:0] csr);
        csrrw = {csr, rs1, 3'b001, rd, 7'b1110011};
    endfunction
    function automatic logic [31:0] csrrs(input logic [4:0] rd, rs1, input logic [11:0] csr);
        csrrs = {csr, rs1, 3'b010, rd, 7'b1110011};
    endfunction
    function automatic logic [31:0] csrrc(input logic [4:0] rd, rs1, input logic [11:0] csr);
        csrrc = {csr, rs1, 3'b011, rd, 7'b1110011};
    endfunction
    function automatic logic [31:0] csrrwi(input logic [4:0] rd, input logic [4:0] zimm, input logic [11:0] csr);
        csrrwi = {csr, zimm, 3'b101, rd, 7'b1110011};
    endfunction
    function automatic logic [31:0] csrrsi(input logic [4:0] rd, input logic [4:0] zimm, input logic [11:0] csr);
        csrrsi = {csr, zimm, 3'b110, rd, 7'b1110011};
    endfunction
    function automatic logic [31:0] csrrci(input logic [4:0] rd, input logic [4:0] zimm, input logic [11:0] csr);
        csrrci = {csr, zimm, 3'b111, rd, 7'b1110011};
    endfunction
    // mret
    function automatic logic [31:0] mret();
        mret = 32'h3020_0073;
    endfunction
    // nop = addi x0, x0, 0
    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        // Address 0 = word 0, etc.
        dut.u_imem.mem[0]  = addi(5'd1,  5'd0, 12'd10);   // x1 = 10
        dut.u_imem.mem[1]  = addi(5'd2,  5'd0, 12'd20);   // x2 = 20
        dut.u_imem.mem[2]  = add (5'd3,  5'd1,  5'd2);    // x3 = x1+x2 = 30
        dut.u_imem.mem[3]  = sw  (5'd0,  5'd3, 12'd0);    // mem[0] = 30
        dut.u_imem.mem[4]  = lw  (5'd4,  5'd0, 12'd0);    // x4 = mem[0] = 30
        dut.u_imem.mem[5]  = sub (5'd5,  5'd4,  5'd1);    // x5 = 30-10 = 20
        dut.u_imem.mem[6]  = slt_f(5'd6, 5'd1,  5'd2);    // x6 = (10<20) = 1
        // BEQ x1,x1,+12 → jump over 2 instructions (PC+12)
        dut.u_imem.mem[7]  = beq(5'd1, 5'd1, 12'sh00c);
        dut.u_imem.mem[8]  = addi(5'd7, 5'd0, 12'd99);    // SKIPPED
        dut.u_imem.mem[9]  = addi(5'd8, 5'd0, 12'd99);    // SKIPPED
        dut.u_imem.mem[10] = addi(5'd9, 5'd0, 12'd42);    // x9  = 42
        // JAL x10, +8 → x10=PC+4, jump to mem[13]
        dut.u_imem.mem[11] = jal(5'd10, 20'sh00008);
        dut.u_imem.mem[12] = addi(5'd11, 5'd0, 12'd99);   // SKIPPED
        dut.u_imem.mem[13] = addi(5'd12, 5'd0, 12'd77);   // x12 = 77
        // CSR tests (mstatus = 0x300)
        dut.u_imem.mem[14] = csrrw (5'd13, 5'd1, 12'h300); // x13=old, mstatus=x1(10)
        dut.u_imem.mem[15] = csrrs (5'd14, 5'd2, 12'h300); // x14=10, mstatus=10|20=30
        dut.u_imem.mem[16] = csrrc (5'd15, 5'd1, 12'h300); // x15=30, mstatus=30&~10=20
        dut.u_imem.mem[17] = csrrwi(5'd16, 5'd5, 12'h300); // x16=20, mstatus=5
        dut.u_imem.mem[18] = csrrsi(5'd17, 5'd2, 12'h300); // x17=5,  mstatus=7
        dut.u_imem.mem[19] = csrrci(5'd18, 5'd1, 12'h300); // x18=7,  mstatus=6

        // Interrupt setup/tests
        dut.u_imem.mem[20] = addi (5'd21, 5'd0, 12'd128);    // x21 = mtvec base (0x80)
        dut.u_imem.mem[21] = csrrw(5'd0,  5'd21, 12'h305);    // mtvec = 0x80
        dut.u_imem.mem[22] = addi (5'd22, 5'd0, 12'd2048);    // x22 = MIE.MEIE bit
        dut.u_imem.mem[23] = csrrw(5'd0,  5'd22, 12'h304);    // mie = 0x800
        dut.u_imem.mem[24] = addi (5'd23, 5'd0, 12'd8);       // x23 = MSTATUS.MIE bit
        dut.u_imem.mem[25] = csrrw(5'd0,  5'd23, 12'h300);    // mstatus = 0x8 (global MIE=1)
        dut.u_imem.mem[26] = addi (5'd28, 5'd0, 12'd1);       // marker before interrupt window
        dut.u_imem.mem[27] = addi (5'd28, 5'd28, 12'd1);      // likely interrupted around here
        dut.u_imem.mem[28] = addi (5'd29, 5'd0, 12'd123);     // must execute after MRET
        dut.u_imem.mem[29] = csrrs(5'd30, 5'd0, 12'h341);     // x30 = mepc
        dut.u_imem.mem[30] = csrrs(5'd31, 5'd0, 12'h342);     // x31 = mcause
        dut.u_imem.mem[31] = NOP;

        // Trap handler @ 0x80 (word 32)
        dut.u_imem.mem[32] = addi (5'd24, 5'd0, 12'd99);      // handler marker
        dut.u_imem.mem[33] = csrrs(5'd26, 5'd0, 12'h342);     // x26 = mcause in handler
        dut.u_imem.mem[34] = csrrs(5'd27, 5'd0, 12'h341);     // x27 = mepc in handler
        dut.u_imem.mem[35] = mret();                          // return from trap

        // Spin forever
        dut.u_imem.mem[36] = NOP;
        dut.u_imem.mem[37] = NOP;
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
        $dumpfile("cpu_wave.vcd");
        $dumpvars(0, tb_cpu);

        // Reset
        rst_n = 0; ext_interrupt = 0; cycle = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Run for 80 cycles (includes interrupt/mret path)
        repeat (80) @(posedge clk);
        cycle = cycle + 1;

        // -------------------------------------------------------
        //  Verify register file contents
        // -------------------------------------------------------
        $display("=== RV32I CPU – Register Dump After 60 Cycles ===");
        $display("x0  = %0d  (expected  0)", dut.u_regfile.regs[0]);
        $display("x1  = %0d  (expected 10)", dut.u_regfile.regs[1]);
        $display("x2  = %0d  (expected 20)", dut.u_regfile.regs[2]);
        $display("x3  = %0d  (expected 30)", dut.u_regfile.regs[3]);
        $display("x4  = %0d  (expected 30)", dut.u_regfile.regs[4]);
        $display("x5  = %0d  (expected 20)", dut.u_regfile.regs[5]);
        $display("x6  = %0d  (expected  1)", dut.u_regfile.regs[6]);
        $display("x7  = %0d  (expected  0 — branch skipped)", dut.u_regfile.regs[7]);
        $display("x8  = %0d  (expected  0 — branch skipped)", dut.u_regfile.regs[8]);
        $display("x9  = %0d  (expected 42)", dut.u_regfile.regs[9]);
        $display("x10 = %0d  (expected PC+4 of JAL instr)", dut.u_regfile.regs[10]);
        $display("x11 = %0d  (expected  0 — JAL skipped)", dut.u_regfile.regs[11]);
        $display("x12 = %0d  (expected 77)", dut.u_regfile.regs[12]);
        $display("x13 = %0d  (expected  0 — CSRRW old)", dut.u_regfile.regs[13]);
        $display("x14 = %0d  (expected 10 — CSRRS old)", dut.u_regfile.regs[14]);
        $display("x15 = %0d  (expected 30 — CSRRC old)", dut.u_regfile.regs[15]);
        $display("x16 = %0d  (expected 20 — CSRRWI old)", dut.u_regfile.regs[16]);
        $display("x17 = %0d  (expected  5 — CSRRSI old)", dut.u_regfile.regs[17]);
        $display("x18 = %0d  (expected  7 — CSRRCI old)", dut.u_regfile.regs[18]);
        $display("x24 = %0d  (expected 99 — trap handler marker)", dut.u_regfile.regs[24]);
        $display("x26 = 0x%08h (expected 0x8000000B — handler mcause)", dut.u_regfile.regs[26]);
        $display("x27 = 0x%08h (expected aligned interrupted PC — handler mepc)", dut.u_regfile.regs[27]);
        $display("x29 = %0d  (expected 123 — post-MRET instruction)", dut.u_regfile.regs[29]);
        $display("x31 = 0x%08h (expected 0x8000000B — final mcause)", dut.u_regfile.regs[31]);
        $display("");

        // Assertions
        if (dut.u_regfile.regs[1]  !== 32'd10) $error("FAIL x1: got %0d", dut.u_regfile.regs[1]);
        if (dut.u_regfile.regs[2]  !== 32'd20) $error("FAIL x2");
        if (dut.u_regfile.regs[3]  !== 32'd30) $error("FAIL x3 (forwarding)");
        if (dut.u_regfile.regs[4]  !== 32'd30) $error("FAIL x4 (load-use)");
        if (dut.u_regfile.regs[5]  !== 32'd20) $error("FAIL x5");
        if (dut.u_regfile.regs[6]  !== 32'd1)  $error("FAIL x6 (SLT)");
        if (dut.u_regfile.regs[7]  !== 32'd0)  $error("FAIL x7 (should be skipped)");
        if (dut.u_regfile.regs[8]  !== 32'd0)  $error("FAIL x8 (should be skipped)");
        if (dut.u_regfile.regs[9]  !== 32'd42) $error("FAIL x9 (branch target)");
        if (dut.u_regfile.regs[11] !== 32'd0)  $error("FAIL x11 (should be JAL-skipped)");
        if (dut.u_regfile.regs[12] !== 32'd77) $error("FAIL x12 (JAL target)");
        if (dut.u_regfile.regs[13] !== 32'd0)  $error("FAIL x13 (CSRRW old)");
        if (dut.u_regfile.regs[14] !== 32'd10) $error("FAIL x14 (CSRRS old)");
        if (dut.u_regfile.regs[15] !== 32'd30) $error("FAIL x15 (CSRRC old)");
        if (dut.u_regfile.regs[16] !== 32'd20) $error("FAIL x16 (CSRRWI old)");
        if (dut.u_regfile.regs[17] !== 32'd5)  $error("FAIL x17 (CSRRSI old)");
        if (dut.u_regfile.regs[18] !== 32'd7)  $error("FAIL x18 (CSRRCI old)");
        if (dut.u_regfile.regs[24] !== 32'd99) $error("FAIL x24 (trap handler did not run)");
        if (dut.u_regfile.regs[26] !== 32'h8000_000B) $error("FAIL x26 (handler mcause)");
        if (dut.u_regfile.regs[27][1:0] !== 2'b00) $error("FAIL x27 (handler mepc not aligned)");
        if (dut.u_regfile.regs[29] !== 32'd123) $error("FAIL x29 (post-MRET path)");
        if (dut.u_regfile.regs[31] !== 32'h8000_000B) $error("FAIL x31 (final mcause)");

        $display("All checks passed – RISC-V CPU simulation complete.");
        $finish;
    end

    // One-shot external interrupt pulse after interrupt-enable code executes
    initial begin
        wait (rst_n == 1'b1);
        wait (dbg_pc == 32'h0000_006c);  // near mem[27]
        @(posedge clk);
        ext_interrupt <= 1'b1;
        @(posedge clk);
        ext_interrupt <= 1'b0;
    end

    // -------------------------------------------------------
    //  Cycle counter display
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n)
            $display("CY%2d | PC=%08h | INSTR=%08h", cycle++, dbg_pc, dbg_instr);
    end

endmodule
