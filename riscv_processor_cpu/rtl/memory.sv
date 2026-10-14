// ============================================================
//  memory.sv - Instruction ROM and byte-addressable data RAM
// ============================================================
`timescale 1ns/1ps

module instr_mem #(
    parameter MEM_FILE = ""
) (
    input  logic        clk,
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] mem [0:1023];

    initial begin
        integer i;
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h0000_0013;
        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    assign instr = mem[addr[11:2]];
endmodule


module data_mem #(
    parameter int XLEN = 32,
    parameter int WORDS = 1024
) (
    input  logic            clk,
    input  logic [XLEN-1:0] addr,
    input  logic [XLEN-1:0] wr_data,
    input  logic            mem_read,
    input  logic            mem_write,
    input  logic [2:0]      funct3,
    output logic [XLEN-1:0] rd_data,
    input  logic            ptw_read,
    input  logic [XLEN-1:0] ptw_addr,
    output logic [31:0]     ptw_rdata
);
    localparam int AW = $clog2(WORDS);
    localparam int XLEN_BYTES = XLEN / 8;
    logic [31:0] mem [0:WORDS-1];
    logic [AW-1:0] widx;
    assign widx = addr[AW+1:2];

    initial begin
        integer i;
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'b0;
    end

    assign ptw_rdata = ptw_read ? mem[ptw_addr[AW+1:2]] : 32'b0;

    // Assemble a little-endian window beginning at the exact byte address.
    // This naturally handles accesses that cross one or more word boundaries.
    logic [XLEN-1:0] raw_value;
    integer read_byte;
    always_comb begin
        raw_value = {XLEN{1'b0}};
        if (mem_read) begin
            for (read_byte = 0; read_byte < XLEN_BYTES; read_byte = read_byte + 1)
                raw_value[read_byte*8 +: 8] =
                    mem[(addr + read_byte) >> 2][((addr + read_byte) & 3)*8 +: 8];
        end
    end

    always_comb begin
        case (funct3)
            3'b000: rd_data = {{(XLEN-8){raw_value[7]}}, raw_value[7:0]};
            3'b001: rd_data = {{(XLEN-16){raw_value[15]}}, raw_value[15:0]};
            3'b010: begin
                if (XLEN == 64)
                    rd_data = {{32{raw_value[31]}}, raw_value[31:0]};
                else
                    rd_data = raw_value;
            end
            3'b011: rd_data = raw_value;
            3'b100: rd_data = {{(XLEN-8){1'b0}}, raw_value[7:0]};
            3'b101: rd_data = {{(XLEN-16){1'b0}}, raw_value[15:0]};
            3'b110: begin
                if (XLEN == 64)
                    rd_data = {32'b0, raw_value[31:0]};
                else
                    rd_data = raw_value;
            end
            default: rd_data = raw_value;
        endcase
    end

    integer store_byte;
    integer store_bytes;
    always_comb begin
        case (funct3[1:0])
            2'b00:   store_bytes = 1;
            2'b01:   store_bytes = 2;
            2'b10:   store_bytes = 4;
            default: store_bytes = XLEN_BYTES;
        endcase
    end

    always_ff @(posedge clk) begin
        if (mem_write) begin
            for (store_byte = 0; store_byte < XLEN_BYTES; store_byte = store_byte + 1) begin
                if (store_byte < store_bytes)
                    mem[(addr + store_byte) >> 2][((addr + store_byte) & 3)*8 +: 8]
                        <= wr_data[store_byte*8 +: 8];
            end
        end
    end
endmodule
