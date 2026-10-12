// ============================================================
//  tb_vector_unit.sv  –  vector_unit against the vec_ref.py vectors
//
//  Generate the vectors first:
//      python tb/vec_ref.py vectors sim/vec_vectors.txt
//  then run with +VECTORS=<path> (default: vec_vectors.txt).
// ============================================================
`timescale 1ns/1ps

module tb_vector_unit;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic         start = 0;
    logic [31:0]  instr, scalar, vl;
    logic [2:0]   sew;
    logic [127:0] vs1, vs2, vd_old, v0;
    logic         busy, done;
    logic [127:0] result;
    logic [31:0]  scalar_out;

    vector_unit dut (.clk(clk), .rst_n(rst_n), .clear(1'b0), .start(start), .instr(instr),
                     .vs1(vs1), .vs2(vs2), .vd_old(vd_old), .v0(v0), .scalar(scalar), .sew(sew), .vl(vl),
                     .busy(busy), .done(done), .result(result), .scalar_out(scalar_out));

    initial begin
        string path;
        integer fd, n, total, fails;
        logic [31:0]  v_instr, v_sew, v_vl, v_scalar, v_sout;
        logic [127:0] v_vs1, v_vs2, v_vd, v_v0, v_res;
        logic         is_vmv_x_s;

        if (!$value$plusargs("VECTORS=%s", path)) path = "vec_vectors.txt";
        fd = $fopen(path, "r");
        if (fd == 0) begin
            $display("ERROR: cannot open %s (run: python tb/vec_ref.py vectors %s)", path, path);
            $finish;
        end
        total = 0; fails = 0;
        #12 rst_n = 1;
        while (!$feof(fd)) begin
            n = $fscanf(fd, "%h %h %h %h %h %h %h %h %h %h\n",
                        v_instr, v_sew, v_vl, v_scalar, v_vs1, v_vs2, v_vd, v_v0, v_res, v_sout);
            if (n == 10) begin
                @(negedge clk);
                instr = v_instr; sew = v_sew[2:0]; vl = v_vl; scalar = v_scalar;
                vs1 = v_vs1; vs2 = v_vs2; vd_old = v_vd; v0 = v_v0;
                start = 1;
                @(negedge clk);
                start = 0;
                while (!done) @(negedge clk);
                total++;
                is_vmv_x_s = (v_instr[14:12] == 3'b010) && (v_instr[31:26] == 6'b010000);
                if (result !== v_res || (is_vmv_x_s && scalar_out !== v_sout)) begin
                    fails++;
                    if (fails <= 15)
                        $display("FAIL instr=%h sew=%0d vl=%0d: got %h/%h expected %h/%h",
                                 v_instr, v_sew, v_vl, result, scalar_out, v_res, v_sout);
                end
            end
        end
        $fclose(fd);
        if (fails == 0 && total > 0)
            $display("All checks passed - vector unit (%0d vectors).", total);
        else
            $display("vector unit FAILED: %0d of %0d vectors", fails, total);
        $finish;
    end

endmodule
