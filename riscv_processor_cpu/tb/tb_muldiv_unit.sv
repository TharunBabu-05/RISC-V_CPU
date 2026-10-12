// ============================================================
//  tb_muldiv_unit.sv  –  Standalone check of muldiv_unit (RV32M)
//  Compares every op against a reference model for corner cases
//  (zero, -1, INT_MIN, divide-by-zero, overflow) plus random values.
// ============================================================
`timescale 1ns/1ps

module tb_muldiv_unit;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic        clear = 0, start = 0;
    logic [2:0]  op;
    logic [31:0] a, b;
    logic        busy, done;
    logic [31:0] result;

    muldiv_unit #(.XLEN(32)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .start(start), .op(op),
        .a(a), .b(b), .busy(busy), .done(done), .result(result)
    );

    function automatic logic [31:0] ref_model(input logic [2:0] f3, input logic [31:0] x, input logic [31:0] y);
        logic signed [63:0] xs, ys;
        logic        [63:0] xu, yu;
        logic signed [63:0] pss;
        logic        [63:0] puu;
        logic signed [63:0] psu;
        begin
            xs = $signed(x); ys = $signed(y);
            xu = {32'b0, x}; yu = {32'b0, y};
            pss = xs * ys;
            psu = xs * $signed(yu);
            puu = xu * yu;
            case (f3)
                3'b000: ref_model = pss[31:0];
                3'b001: ref_model = pss[63:32];
                3'b010: ref_model = psu[63:32];
                3'b011: ref_model = puu[63:32];
                3'b100: ref_model = (y == 0) ? 32'hFFFF_FFFF :
                                    (x == 32'h8000_0000 && y == 32'hFFFF_FFFF) ? 32'h8000_0000 :
                                    32'($signed(x) / $signed(y));
                3'b101: ref_model = (y == 0) ? 32'hFFFF_FFFF : x / y;
                3'b110: ref_model = (y == 0) ? x :
                                    (x == 32'h8000_0000 && y == 32'hFFFF_FFFF) ? 32'h0 :
                                    32'($signed(x) % $signed(y));
                default: ref_model = (y == 0) ? x : x % y;
            endcase
        end
    endfunction

    int errors = 0;
    int checks = 0;

    task automatic run_op(input logic [2:0] f3, input logic [31:0] x, input logic [31:0] y);
        logic [31:0] expected;
        int cycles;
        begin
            expected = ref_model(f3, x, y);
            @(negedge clk);
            op = f3; a = x; b = y; start = 1;
            @(negedge clk);
            start = 0;
            a = 32'hDEAD_BEEF; b = 32'hBAD0_BAD0; // operands must have been captured
            cycles = 1;
            while (!done && cycles <= 100) begin
                @(negedge clk);
                cycles++;
            end
            checks++;
            if (!done) begin
                $error("TIMEOUT op=%0d a=%h b=%h", f3, x, y);
                errors++;
            end else if (result !== expected) begin
                $error("MISMATCH op=%0d a=%h b=%h got=%h exp=%h", f3, x, y, result, expected);
                errors++;
            end
            @(negedge clk); // let the unit return to idle
        end
    endtask

    logic [31:0] corners [0:7];

    initial begin
        corners[0] = 32'h0;          corners[1] = 32'h1;
        corners[2] = 32'hFFFF_FFFF;  corners[3] = 32'h8000_0000;
        corners[4] = 32'h7FFF_FFFF;  corners[5] = 32'h2;
        corners[6] = 32'hFFFF_FFFE;  corners[7] = 32'h0001_0000;
        #12 rst_n = 1;

        for (int f = 0; f < 8; f++)
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 8; j++)
                    run_op(f[2:0], corners[i], corners[j]);

        for (int n = 0; n < 400; n++)
            run_op($urandom_range(0, 7), $urandom, (n % 4 == 0) ? $urandom_range(0, 15) : $urandom);

        // A flush mid-divide must abort cleanly and leave the unit idle
        @(negedge clk);
        op = 3'b100; a = 100; b = 7; start = 1;
        @(negedge clk); start = 0;
        repeat (5) @(negedge clk);
        clear = 1; @(negedge clk); clear = 0;
        if (busy) begin $error("unit still busy after clear"); errors++; end
        run_op(3'b100, 100, 7);

        if (errors == 0)
            $display("All checks passed - muldiv unit (%0d ops).", checks);
        else
            $display("muldiv unit FAILED: %0d errors / %0d ops", errors, checks);
        $finish;
    end

endmodule
