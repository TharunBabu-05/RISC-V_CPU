// ============================================================
//  tb_fpu_unit.sv  –  fpu_unit against the fpu_ref.py vectors
//
//  Generate the vectors first:
//      python tb/fpu_ref.py vectors sim/fpu_vectors.txt
//  then run with +VECTORS=<path> (default: fpu_vectors.txt).
//  Every vector checks the result bits and all five fflags.
// ============================================================
`timescale 1ns/1ps

module tb_fpu_unit;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic        start = 0;
    logic [4:0]  op;
    logic [2:0]  rm;
    logic [31:0] a, b, c, x;
    logic        busy, done;
    logic [31:0] result;
    logic [4:0]  flags;

    fpu_unit dut (.clk(clk), .rst_n(rst_n), .clear(1'b0), .start(start), .op(op), .rm(rm),
                  .a(a), .b(b), .c(c), .x(x), .busy(busy), .done(done), .result(result), .flags(flags));

    function automatic string op_name(input integer i);
        case (i)
            0: op_name = "FADD";
            1: op_name = "FSUB";
            2: op_name = "FMUL";
            3: op_name = "FDIV";
            4: op_name = "FSQRT";
            5: op_name = "FMIN";
            6: op_name = "FMAX";
            7: op_name = "FSGNJ";
            8: op_name = "FSGNJN";
            9: op_name = "FSGNJX";
            10: op_name = "FEQ";
            11: op_name = "FLT";
            12: op_name = "FLE";
            13: op_name = "FCLASS";
            14: op_name = "FCVT.W.S";
            15: op_name = "FCVT.WU.S";
            16: op_name = "FCVT.S.W";
            17: op_name = "FCVT.S.WU";
            18: op_name = "FMV.X.W";
            19: op_name = "FMV.W.X";
            20: op_name = "FMADD";
            21: op_name = "FMSUB";
            22: op_name = "FNMSUB";
            23: op_name = "FNMADD";
            default: op_name = "?";
        endcase
    endfunction

    integer per_op_total [0:23];
    integer per_op_fail  [0:23];

    initial begin
        string path;
        integer fd, n, total, fails;
        logic [31:0] v_op, v_rm, v_a, v_b, v_c, v_x, v_res, v_fl;

        if (!$value$plusargs("VECTORS=%s", path)) path = "fpu_vectors.txt";
        fd = $fopen(path, "r");
        if (fd == 0) begin
            $display("ERROR: cannot open %s (run: python tb/fpu_ref.py vectors %s)", path, path);
            $finish;
        end
        for (int i = 0; i < 24; i++) begin per_op_total[i] = 0; per_op_fail[i] = 0; end
        total = 0; fails = 0;

        #12 rst_n = 1;
        while (!$feof(fd)) begin
            n = $fscanf(fd, "%h %h %h %h %h %h %h %h\n", v_op, v_rm, v_a, v_b, v_c, v_x, v_res, v_fl);
            if (n == 8) begin
            @(negedge clk);
            op = v_op[4:0]; rm = v_rm[2:0]; a = v_a; b = v_b; c = v_c; x = v_x;
            start = 1;
            @(negedge clk);
            start = 0;
            while (!done) @(negedge clk);
            total++;
            per_op_total[v_op]++;
            if (result !== v_res || flags !== v_fl[4:0]) begin
                fails++;
                per_op_fail[v_op]++;
                if (fails <= 20)
                    $display("FAIL %-9s rm=%0d a=%h b=%h c=%h x=%h: got %h/%b expected %h/%b",
                             op_name(v_op), v_rm, v_a, v_b, v_c, v_x, result, flags, v_res, v_fl[4:0]);
            end
            end
        end
        $fclose(fd);

        for (int i = 0; i < 24; i++)
            $display("  %-9s %6d vectors, %4d failures", op_name(i), per_op_total[i], per_op_fail[i]);
        if (fails == 0 && total > 0)
            $display("All checks passed - FPU unit (%0d vectors).", total);
        else
            $display("FPU unit FAILED: %0d of %0d vectors", fails, total);
        $finish;
    end

endmodule
