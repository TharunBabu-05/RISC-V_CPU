// ============================================================
//  memory.sv  –  Instruction memory (ROM) + Data memory (RAM)
//  Byte-addressable, 32-bit aligned accesses
//  Instruction memory: 4 KB (1024 words), initialised from file
//  Data memory: 4 KB (1024 words)
// ============================================================
`timescale 1ns/1ps

// ----------------------------------------------------------
//  Instruction memory  (synchronous read for pipeline)
// ----------------------------------------------------------
module instr_mem #(
    parameter MEM_FILE = ""     // optional hex init file path
) (
    input  logic        clk,
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] mem [0:1023];

    initial begin
        integer i;
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h0000_0013; // NOP (ADDI x0,x0,0)
        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    // Asynchronous read (combinatorial) — simplest model
    assign instr = mem[addr[11:2]]; // word-aligned fetch

endmodule


// ----------------------------------------------------------
//  Data memory  (synchronous write, async read)
//  Supports byte/halfword/word and optional 64-bit (LD/SD) when XLEN=64
//  via funct3 passed from MEM stage
// ----------------------------------------------------------
module data_mem #(
    parameter int XLEN = 32
) (
    input  logic        clk,
    input  logic [XLEN-1:0] addr,
    input  logic [XLEN-1:0] wr_data,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [2:0]  funct3,     // access width / signedness
    output logic [XLEN-1:0] rd_data,
    input  logic        ptw_read,
    input  logic [XLEN-1:0] ptw_addr,
    output logic [31:0] ptw_rdata
);
    logic [31:0] mem [0:1023];

    initial begin
        integer i;
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'b0;
    end

    assign ptw_rdata = ptw_read ? mem[ptw_addr[11:2]] : 32'b0;

    generate
        if (XLEN == 64) begin : gen_mem64
            // Write (synchronous)
            always_ff @(posedge clk) begin
                if (mem_write) begin
                    case (funct3)
                        3'b000: begin   // SB
                            case (addr[1:0])
                                2'b00: mem[addr[11:2]][7:0]   <= wr_data[7:0];
                                2'b01: mem[addr[11:2]][15:8]  <= wr_data[7:0];
                                2'b10: mem[addr[11:2]][23:16] <= wr_data[7:0];
                                2'b11: mem[addr[11:2]][31:24] <= wr_data[7:0];
                            endcase
                        end
                        3'b001: begin   // SH
                            case (addr[1])
                                1'b0: mem[addr[11:2]][15:0]  <= wr_data[15:0];
                                1'b1: mem[addr[11:2]][31:16] <= wr_data[15:0];
                            endcase
                        end
                        3'b010: mem[addr[11:2]] <= wr_data[31:0]; // SW
                        3'b011: begin // SD
                            mem[addr[11:2]]     <= wr_data[31:0];
                            mem[addr[11:2] + 1] <= wr_data[63:32];
                        end
                        default: mem[addr[11:2]] <= wr_data[31:0];
                    endcase
                end
            end

            // Read (combinatorial)
            logic [31:0] raw_word;
            logic [63:0] raw_dword;
            assign raw_word  = mem_read ? mem[addr[11:2]] : 32'b0;
            assign raw_dword = mem_read ? {mem[addr[11:2] + 1], mem[addr[11:2]]} : 64'b0;

            always_comb begin
                case (funct3)
                    3'b000: begin // LB – sign-extend byte
                        case (addr[1:0])
                            2'b00: rd_data = {{56{raw_word[7]}},  raw_word[7:0]};
                            2'b01: rd_data = {{56{raw_word[15]}}, raw_word[15:8]};
                            2'b10: rd_data = {{56{raw_word[23]}}, raw_word[23:16]};
                            2'b11: rd_data = {{56{raw_word[31]}}, raw_word[31:24]};
                            default: rd_data = 64'b0;
                        endcase
                    end
                    3'b001: begin // LH – sign-extend halfword
                        case (addr[1])
                            1'b0: rd_data = {{48{raw_word[15]}}, raw_word[15:0]};
                            1'b1: rd_data = {{48{raw_word[31]}}, raw_word[31:16]};
                            default: rd_data = 64'b0;
                        endcase
                    end
                    3'b010: rd_data = {{32{raw_word[31]}}, raw_word};      // LW
                    3'b011: rd_data = raw_dword;                           // LD
                    3'b100: begin // LBU – zero-extend byte
                        case (addr[1:0])
                            2'b00: rd_data = {56'b0, raw_word[7:0]};
                            2'b01: rd_data = {56'b0, raw_word[15:8]};
                            2'b10: rd_data = {56'b0, raw_word[23:16]};
                            2'b11: rd_data = {56'b0, raw_word[31:24]};
                            default: rd_data = 64'b0;
                        endcase
                    end
                    3'b101: begin // LHU – zero-extend halfword
                        case (addr[1])
                            1'b0: rd_data = {48'b0, raw_word[15:0]};
                            1'b1: rd_data = {48'b0, raw_word[31:16]};
                            default: rd_data = 64'b0;
                        endcase
                    end
                    3'b110: rd_data = {32'b0, raw_word};                    // LWU
                    default: rd_data = raw_dword;
                endcase
            end
        end else begin : gen_mem32
            // Write (synchronous)
            always_ff @(posedge clk) begin
                if (mem_write) begin
                    case (funct3)
                        3'b000: begin   // SB
                            case (addr[1:0])
                                2'b00: mem[addr[11:2]][7:0]   <= wr_data[7:0];
                                2'b01: mem[addr[11:2]][15:8]  <= wr_data[7:0];
                                2'b10: mem[addr[11:2]][23:16] <= wr_data[7:0];
                                2'b11: mem[addr[11:2]][31:24] <= wr_data[7:0];
                            endcase
                        end
                        3'b001: begin   // SH
                            case (addr[1])
                                1'b0: mem[addr[11:2]][15:0]  <= wr_data[15:0];
                                1'b1: mem[addr[11:2]][31:16] <= wr_data[15:0];
                            endcase
                        end
                        3'b010: mem[addr[11:2]] <= wr_data[31:0]; // SW
                        default: mem[addr[11:2]] <= wr_data[31:0];
                    endcase
                end
            end

            // Read (combinatorial)
            logic [31:0] raw_word;
            assign raw_word = mem_read ? mem[addr[11:2]] : 32'b0;

            always_comb begin
                case (funct3)
                    3'b000: begin // LB – sign-extend byte
                        case (addr[1:0])
                            2'b00: rd_data = {{24{raw_word[7]}},  raw_word[7:0]};
                            2'b01: rd_data = {{24{raw_word[15]}}, raw_word[15:8]};
                            2'b10: rd_data = {{24{raw_word[23]}}, raw_word[23:16]};
                            2'b11: rd_data = {{24{raw_word[31]}}, raw_word[31:24]};
                            default: rd_data = 32'b0;
                        endcase
                    end
                    3'b001: begin // LH – sign-extend halfword
                        case (addr[1])
                            1'b0: rd_data = {{16{raw_word[15]}}, raw_word[15:0]};
                            1'b1: rd_data = {{16{raw_word[31]}}, raw_word[31:16]};
                            default: rd_data = 32'b0;
                        endcase
                    end
                    3'b010: rd_data = raw_word;                                    // LW
                    3'b100: begin // LBU – zero-extend byte
                        case (addr[1:0])
                            2'b00: rd_data = {24'b0, raw_word[7:0]};
                            2'b01: rd_data = {24'b0, raw_word[15:8]};
                            2'b10: rd_data = {24'b0, raw_word[23:16]};
                            2'b11: rd_data = {24'b0, raw_word[31:24]};
                            default: rd_data = 32'b0;
                        endcase
                    end
                    3'b101: begin // LHU – zero-extend halfword
                        case (addr[1])
                            1'b0: rd_data = {16'b0, raw_word[15:0]};
                            1'b1: rd_data = {16'b0, raw_word[31:16]};
                            default: rd_data = 32'b0;
                        endcase
                    end
                    default: rd_data = raw_word;
                endcase
            end
        end
    endgenerate

endmodule
