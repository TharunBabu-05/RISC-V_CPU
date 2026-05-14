// ============================================================
//  icache.sv  –  Instruction cache wrapper (pass-through)
// ============================================================
`timescale 1ns/1ps

module icache #(
    parameter int XLEN = 32,
    parameter IMEM_FILE = ""
) (
    input  logic        clk,
    input  logic [XLEN-1:0] addr,
    output logic [31:0] instr
);

    // Pass-through instruction storage (replace with real cache later)
    logic [31:0] mem [0:1023];

    initial begin
        integer i;
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h0000_0013; // NOP (ADDI x0,x0,0)
        if (IMEM_FILE != "")
            $readmemh(IMEM_FILE, mem);
    end

    assign instr = mem[addr[11:2]];

endmodule
