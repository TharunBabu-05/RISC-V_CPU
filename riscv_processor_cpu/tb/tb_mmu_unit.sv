// ============================================================
//  tb_mmu_unit.sv  –  Sv32 MMU unit test (data side)
//
//  Drives mmu.sv directly with a page-table memory model.
//    A: 4 MiB superpage   VA 0x0040_5678 -> PA 0x0080_5678
//    B: read-only superpage (R=1,W=0,X=0) is a valid leaf
//    C: misaligned superpage (PPN[0] != 0) must page-fault
//    D: 4 KiB page with ASID != 0 must fill the TLB and then hit
// ============================================================
`timescale 1ns/1ps

module tb_mmu_unit;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    localparam logic [8:0]  ASID = 9'd5;
    localparam logic [21:0] ROOT_PPN = 22'd1;                  // root table @0x1000
    localparam logic [31:0] SATP = {1'b1, ASID, ROOT_PPN};

    localparam logic [31:0] V = 32'h01, R = 32'h02, W = 32'h04, X = 32'h08, A = 32'h40, D = 32'h80;

    logic [31:0] satp = 32'h0;
    logic        data_req = 0, data_write = 0;
    logic [31:0] data_vaddr = 0;
    logic [31:0] inst_paddr, data_paddr, ptw_addr;
    logic        inst_ready, inst_fault, data_ready, data_fault, stall, ptw_read;
    logic [31:0] ptw_rdata;

    mmu #(.XLEN(32)) dut (
        .clk(clk), .rst_n(rst_n), .satp(satp), .current_priv(2'b01), .sfence(1'b0),
        .inst_vaddr(32'h0), .inst_req(1'b0), .inst_paddr(inst_paddr), .inst_ready(inst_ready), .inst_fault(inst_fault),
        .data_vaddr(data_vaddr), .data_req(data_req), .data_write(data_write),
        .data_paddr(data_paddr), .data_ready(data_ready), .data_fault(data_fault),
        .stall(stall), .ptw_read(ptw_read), .ptw_addr(ptw_addr), .ptw_rdata(ptw_rdata)
    );

    // Page-table memory (16 KiB)
    logic [31:0] ptmem [0:4095];
    assign ptw_rdata = ptw_read ? ptmem[ptw_addr[13:2]] : 32'h0;

    function automatic [31:0] pte(input [21:0] ppn, input [31:0] flags);
        pte = {ppn, 10'b0} | flags;
    endfunction

    integer errors = 0;

    // Issue one data access; return the translated address or flag a fault/timeout.
    task automatic access(input string what, input [31:0] va, input logic expect_fault, input [31:0] expect_pa,
                          input int max_ptw_reads);
        logic got_fault, got_ready;
        logic [31:0] pa;
        int reads;
        got_fault = 0; got_ready = 0; pa = 0; reads = 0;
        @(negedge clk);
        data_vaddr = va; data_req = 1;
        for (int c = 0; c < 30 && !got_ready && !got_fault; c++) begin
            #1;
            if (ptw_read) reads++;
            if (data_fault) got_fault = 1;
            else if (data_ready) begin got_ready = 1; pa = data_paddr; end
            @(negedge clk);
        end
        data_req = 0;
        if (expect_fault) begin
            if (!got_fault) begin errors++; $error("FAIL %s: expected page fault (ready=%0d pa=%h)", what, got_ready, pa); end
            else $display("PASS %s: page fault", what);
        end else if (!got_ready) begin
            errors++; $error("FAIL %s: no translation (fault=%0d, timed out=%0d)", what, got_fault, !got_fault);
        end else if (pa !== expect_pa) begin
            errors++; $error("FAIL %s: PA %h expected %h", what, pa, expect_pa);
        end else if (reads > max_ptw_reads) begin
            errors++; $error("FAIL %s: %0d page-table reads, expected at most %0d (TLB entry not reused)", what, reads, max_ptw_reads);
        end else
            $display("PASS %s: VA %h -> PA %h (%0d page-table reads)", what, va, pa, reads);
        repeat (2) @(negedge clk);
    endtask

    initial begin
        for (int i = 0; i < 4096; i++) ptmem[i] = 32'h0;
        // Root table at PPN 1 (word 0x400). Entry index = VPN[1].
        ptmem[12'h400 + 1] = pte({12'h002, 10'h000}, V|R|W|A|D);   // A: superpage -> PA 0x0080_0000
        ptmem[12'h400 + 2] = pte({12'h003, 10'h000}, V|R|A);       // B: read-only superpage
        ptmem[12'h400 + 3] = pte({12'h004, 10'h001}, V|R|W|A|D);   // C: misaligned superpage
        ptmem[12'h400 + 4] = pte(22'd2, V);                        // D: pointer to L0 table @0x2000
        ptmem[12'h800 + 3] = pte(22'h00010, V|R|W|A|D);            // D: L0[VPN0=3] -> PA 0x0001_0000

        #12 rst_n = 1;
        @(negedge clk) satp = SATP;
        repeat (2) @(negedge clk);

        access("A superpage translation",     32'h0040_5678, 0, 32'h0080_5678, 1);
        access("B read-only superpage load",  32'h0080_1234, 0, 32'h00C0_1234, 1);
        access("C misaligned superpage",      32'h00C0_0010, 1, 32'h0, 1);
        access("D 4KiB page, ASID 5 (fill)",  32'h0100_3010, 0, 32'h0001_0010, 2);
        access("D 4KiB page, ASID 5 (TLB hit)", 32'h0100_3020, 0, 32'h0001_0020, 0);

        if (errors == 0) $display("All checks passed - MMU unit.");
        else             $display("MMU unit FAILED: %0d errors", errors);
        $finish;
    end
endmodule
