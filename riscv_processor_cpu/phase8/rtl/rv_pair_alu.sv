// Pair only nontrapping RV32I integer instructions. Memory, control flow,
// system and M-extension operations execute alone in the existing lane.
`timescale 1ns/1ps
module rv_pair_decode (
    input wire [31:0] first, second,
    output wire eligible
);
    function automatic simple(input [31:0] insn);
        begin
            case (insn[6:0])
                7'h37, 7'h17: simple = 1;
                7'h13: case (insn[14:12])
                    3'h1: simple = insn[31:25] == 0;
                    3'h5: simple = insn[31:25] == 0 || insn[31:25] == 7'h20;
                    default: simple = 1;
                endcase
                7'h33: simple = insn[31:25] == 0 ||
                    (insn[31:25] == 7'h20 && (insn[14:12] == 0 || insn[14:12] == 5));
                default: simple = 0;
            endcase
        end
    endfunction
    wire use_rs1 = second[6:0] == 7'h13 || second[6:0] == 7'h33;
    wire use_rs2 = second[6:0] == 7'h33;
    wire raw = first[11:7] != 0 &&
        ((use_rs1 && first[11:7] == second[19:15]) ||
         (use_rs2 && first[11:7] == second[24:20]));
    wire waw = first[11:7] != 0 && first[11:7] == second[11:7];
    assign eligible = simple(first) && simple(second) && !raw && !waw;
endmodule

module rv_pair_alu (
    input wire [31:0] instr, pc, rs1, rs2,
    output reg [31:0] result
);
    wire [31:0] immediate = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] b = instr[6:0] == 7'h13 ? immediate : rs2;
    always @* begin
        if (instr[6:0] == 7'h37) result = {instr[31:12], 12'b0};
        else if (instr[6:0] == 7'h17) result = pc + {instr[31:12], 12'b0};
        else case (instr[14:12])
            0: result = (instr[6:0] == 7'h33 && instr[30]) ? rs1 - b : rs1 + b;
            1: result = rs1 << b[4:0];
            2: result = {31'b0, $signed(rs1) < $signed(b)};
            3: result = {31'b0, rs1 < b};
            4: result = rs1 ^ b;
            5: if (instr[30]) result = $signed(rs1) >>> b[4:0];
               else result = rs1 >> b[4:0];
            6: result = rs1 | b;
            7: result = rs1 & b;
        endcase
    end
endmodule
