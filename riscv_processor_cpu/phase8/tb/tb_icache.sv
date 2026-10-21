`timescale 1ns/1ps
module tb_icache;
    reg clk=0, rst_n=0, invalidate=0, req_valid=0, req_cacheable=1, rsp_ready=0;
    always #5 clk=~clk;
    reg [31:0] req_addr=0, mem_rsp_data=0;
    reg mem_req_ready=0, mem_rsp_valid=0, mem_rsp_err=0;
    wire req_ready, rsp_valid, rsp_pair, rsp_err, mem_req_valid, mem_rsp_ready;
    wire [31:0] rsp_data, rsp_second, mem_req_addr;
    integer reads=0, ticks=0, wait_count=0;
    reg pending=0, inject_error=0;
    reg [31:0] saved, salt=0;
    rv_icache dut(.*);
    function automatic [31:0] value(input [31:0] addr);
        value = addr ^ 32'hdeadc000 ^ salt;
    endfunction
    always @* mem_req_ready=!pending && ticks%3 != 0;
    always @(posedge clk) begin
        ticks<=ticks+1;
        if(mem_req_valid && mem_req_ready) begin
            saved<=mem_req_addr; pending<=1; wait_count<=3; reads<=reads+1;
        end
        if(pending && !mem_rsp_valid) begin
            if(wait_count==0) begin
                mem_rsp_data<=value(saved);
                mem_rsp_err<=inject_error && !saved[2];
                mem_rsp_valid<=1;
            end else wait_count<=wait_count-1;
        end else if(mem_rsp_valid && mem_rsp_ready) begin
            mem_rsp_valid<=0; pending<=0;
        end
    end
    task automatic fetch(input [31:0] addr, input bit pair_expected, input bit error_expected);
        reg [31:0] held;
        begin
            @(posedge clk); #1;
            req_addr=addr; req_valid=1;
            do @(posedge clk); while(!req_ready);
            #1 req_valid=0;
            wait(rsp_valid); #1;
            if(rsp_err !== error_expected || rsp_pair !== pair_expected ||
               rsp_data !== value(addr)) $fatal(1,"cache result addr=%h data=%h pair=%b err=%b",addr,rsp_data,rsp_pair,rsp_err);
            if(pair_expected && rsp_second !== value(addr+4)) $fatal(1,"second word");
            held=rsp_data;
            repeat(4) begin
                @(posedge clk); #1;
                if(!rsp_valid || rsp_data !== held) $fatal(1,"response changed under backpressure");
            end
            rsp_ready=1;
            @(posedge clk); #1 rsp_ready=0;
        end
    endtask
    task automatic fence;
        @(posedge clk); #1 invalidate=1;
        @(posedge clk); #1 invalidate=0;
    endtask
    integer before_reads;
    initial begin
        repeat(3) @(posedge clk); #1 rst_n=1;
        fetch(32'h80000000,1,0);
        if(reads!=2) $fatal(1,"refill count");
        fetch(32'h80000004,0,0);
        fetch(32'h80000000,1,0);
        if(reads!=2) $fatal(1,"hit went to memory");
        fetch(32'h80002000,1,0);
        fetch(32'h80000000,1,0);
        if(reads!=6) $fatal(1,"conflict did not refill");
        fence(); salt=32'h12340000;
        fetch(32'h80000000,1,0);
        if(reads!=8) $fatal(1,"fence did not invalidate");
        req_cacheable=0;
        fetch(32'h10000000,0,0); fetch(32'h10000000,0,0);
        if(reads!=10) $fatal(1,"bypass was cached");
        req_cacheable=1; inject_error=1;
        fetch(32'h80000008,0,1);
        inject_error=0; before_reads=reads;
        fetch(32'h80000008,1,0);
        if(reads!=before_reads+2) $fatal(1,"error refill cached");
        before_reads=reads;
        fork
            fetch(32'h80000010,1,0);
            begin wait(dut.state==3); fence(); end
        join
        fetch(32'h80000010,1,0);
        if(reads!=before_reads+4) $fatal(1,"inflight fence revalidated old line");
        $display("PASS: 8 KiB cache hits/conflicts/bypass/errors/backpressure/inflight FENCE.I");
        $finish;
    end
    initial begin #100000; $fatal(1,"cache test timeout state=%d reads=%d pending=%b req=%b rsp=%b addr=%h",dut.state,reads,pending,mem_req_valid,mem_rsp_valid,req_addr); end
endmodule
