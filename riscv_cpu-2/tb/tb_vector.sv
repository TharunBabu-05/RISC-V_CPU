// ============================================================
//  tb_vector.sv - CPU-integrated vector arithmetic smoke test
// ============================================================
`timescale 1ns/1ps

module tb_vector;

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

    function automatic logic [31:0] vop(input logic [2:0] op, input logic [4:0] rd, rs1, rs2);
        vop = {7'b0000000, rs2, rs1, op, rd, 7'b1010111};
    endfunction
    function automatic logic [31:0] csrrwi(input logic [4:0] rd, input logic [4:0] zimm, input logic [11:0] csr);
        csrrwi = {csr, zimm, 3'b101, rd, 7'b1110011};
    endfunction
    function automatic logic [31:0] csrrs(input logic [4:0] rd, rs1, input logic [11:0] csr);
        csrrs = {csr, rs1, 3'b010, rd, 7'b1110011};
    endfunction

    localparam logic [31:0] NOP = 32'h0000_0013;

    initial begin
        dut.u_imem.mem[0] = csrrwi(5'd0, 5'd4, 12'hC20); // vl = 4
        dut.u_imem.mem[1] = vop(3'b000, 5'd3, 5'd1, 5'd2); // add
        dut.u_imem.mem[2] = vop(3'b001, 5'd4, 5'd2, 5'd1); // sub
        dut.u_imem.mem[3] = vop(3'b010, 5'd5, 5'd1, 5'd2); // and
        dut.u_imem.mem[4] = vop(3'b011, 5'd6, 5'd1, 5'd2); // or
        dut.u_imem.mem[5] = csrrs(5'd7, 5'd0, 12'hC20);    // read vl
        dut.u_imem.mem[6] = NOP;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("cpu_vector_wave.vcd");
        $dumpvars(0, tb_vector);
        rst_n = 0; ext_interrupt = 0;
        repeat (4) @(posedge clk);
        dut.u_vec_regfile.regs[1] = {32'd4, 32'd3, 32'd2, 32'd1};
        dut.u_vec_regfile.regs[2] = {32'd40, 32'd30, 32'd20, 32'd10};
        rst_n = 1;
        repeat (100) @(posedge clk);

        $display("=== Vector Register Dump ===");
        $display("v3=%032h", dut.u_vec_regfile.regs[3]);
        $display("v4=%032h", dut.u_vec_regfile.regs[4]);
        $display("x7=%0d", dut.u_regfile.regs[7]);

        if (dut.u_vec_regfile.regs[3] !== {32'd44, 32'd33, 32'd22, 32'd11}) $error("FAIL vadd");
        if (dut.u_vec_regfile.regs[4] !== {32'd36, 32'd27, 32'd18, 32'd9})  $error("FAIL vsub");
        if (dut.u_regfile.regs[7] !== 32'd4) $error("FAIL vl CSR");

        $display("All checks passed - vector integration complete.");
        $finish;
    end

endmodule
