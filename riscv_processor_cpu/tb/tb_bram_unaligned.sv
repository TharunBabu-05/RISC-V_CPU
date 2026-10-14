`timescale 1ns/1ps

module tb_bram_unaligned;
    logic clk=0;
    always #5 clk=~clk;
    logic [31:0] a_addr, a_rdata, b_addr, b_wdata, b_rdata;
    logic [3:0] b_we;
    logic b_re;
    integer errors=0;

    bram #(.SIZE_BYTES(64), .INIT_FILE("")) dut (.*);

    task write_bytes(input [31:0] a, input [31:0] d, input [3:0] we);
        @(negedge clk); b_addr=a; b_wdata=d; b_we=we;
        @(posedge clk); #1; b_we=0;
    endtask
    task read_word(input [31:0] a, input [31:0] expected, input string name);
        @(negedge clk); b_addr=a; b_re=1;
        @(posedge clk); #1; b_re=0;
        if (b_rdata !== expected) begin $error("FAIL %s: %h != %h",name,b_rdata,expected); errors++; end
        else $display("PASS %s",name);
    endtask

    initial begin
        a_addr=0; b_addr=0; b_wdata=0; b_we=0; b_re=0;
        for (int i=0;i<16;i++) begin dut.even_mem[i]=0; dut.odd_mem[i]=0; end
        write_bytes(0, 32'h44332211, 4'b1111);
        write_bytes(4, 32'h88776655, 4'b1111);
        read_word(1, 32'h55443322, "cross-word read");
        write_bytes(2, 32'haabbccdd, 4'b1111);
        read_word(2, 32'haabbccdd, "cross-word write/read");
        read_word(0, 32'hccdd2211, "lower word preserved lanes");
        read_word(4, 32'h8877aabb, "upper word preserved lanes");
        if(errors==0) $display("All checks passed - banked BRAM unaligned access.");
        else $display("BRAM unaligned FAILED: %0d errors",errors);
        $finish;
    end
endmodule
