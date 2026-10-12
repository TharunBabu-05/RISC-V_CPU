// ============================================================
//  vector_regfile.sv - 32-entry vector register file (VLEN bits)
//  Read ports: vs1, vs2, vd (old value / vs3 store data) and the
//  v0 mask register, all with write-through bypass.
// ============================================================
`timescale 1ns/1ps

module vector_regfile #(
    parameter int VLEN = 128
) (
    input  logic            clk,
    input  logic            rst_n,
    input  logic [4:0]      rs1_addr,
    output logic [VLEN-1:0] rs1_data,
    input  logic [4:0]      rs2_addr,
    output logic [VLEN-1:0] rs2_data,
    input  logic [4:0]      rd_raddr,
    output logic [VLEN-1:0] rd_rdata,
    output logic [VLEN-1:0] v0_data,
    input  logic [4:0]      rd_addr,
    input  logic [VLEN-1:0] rd_data,
    input  logic            reg_write
);

    logic [VLEN-1:0] regs [0:31];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i = i + 1)
                regs[i] <= {VLEN{1'b0}};
        end else if (reg_write) begin
            regs[rd_addr] <= rd_data;
        end
    end

    assign rs1_data = (reg_write && rd_addr == rs1_addr) ? rd_data : regs[rs1_addr];
    assign rs2_data = (reg_write && rd_addr == rs2_addr) ? rd_data : regs[rs2_addr];
    assign rd_rdata = (reg_write && rd_addr == rd_raddr) ? rd_data : regs[rd_raddr];
    assign v0_data  = (reg_write && rd_addr == 5'd0)     ? rd_data : regs[0];

endmodule
