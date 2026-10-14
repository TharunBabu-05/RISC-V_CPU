`timescale 1ns/1ps

module tb_pmp;
    logic [31:0] addr;
    logic [3:0] size;
    logic rd, wr, ex;
    logic [1:0] priv;
    logic [31:0] cfg, a0, a1, a2, a3;
    logic allow;
    integer errors = 0;

    pmp_unit dut (
        .addr(addr), .access_size(size), .access_r(rd), .access_w(wr), .access_x(ex),
        .current_priv(priv), .pmpcfg0(cfg), .pmpaddr0(a0), .pmpaddr1(a1),
        .pmpaddr2(a2), .pmpaddr3(a3), .allow(allow)
    );

    task check(input string name, input logic expected);
        #1;
        if (allow !== expected) begin
            $error("FAIL %s: allow=%b expected=%b", name, allow, expected);
            errors++;
        end else $display("PASS %s", name);
    endtask

    initial begin
        addr=0; size=4; rd=1; wr=0; ex=0; priv=2'b01;
        cfg=0; a0=0; a1=0; a2=0; a3=0;
        check("empty PMP preserves flat map", 1);

        cfg[7:0] = 8'h0f; // TOR, RWX
        a0 = 32'h0000_0400; // [0, 0x1000)
        addr = 32'h0000_0800;
        check("TOR read inside", 1);
        addr = 32'h0000_1000;
        check("TOR unmatched S access", 0);

        addr = 32'h0000_0800; rd=0; ex=1;
        cfg[7:0] = 8'h0b; // TOR, RW only
        check("TOR execute permission", 0);
        priv = 2'b11;
        check("M-mode bypasses unlocked entry", 1);
        cfg[7:0] = 8'h8b;
        check("locked entry constrains M-mode", 0);

        priv=2'b01; rd=1; ex=0; cfg=32'h0000_0019; // NAPOT, R
        a0=32'h0000_0801; // 16 bytes at 0x2000
        addr=32'h0000_200f; size=1;
        check("NAPOT last byte", 1);
        addr=32'h0000_2010;
        check("NAPOT upper bound", 0);

        // riscv-tests programs this canonical all-memory RV32 region.
        cfg=32'h0000_001f; a0=32'h7fff_ffff;
        addr=32'h8000_2001; size=2; rd=1; wr=0; ex=0; priv=2'b00;
        check("NAPOT full RV32 address space", 1);

        if (errors == 0) $display("All checks passed - PMP.");
        else $display("PMP FAILED: %0d errors", errors);
        $finish;
    end
endmodule
