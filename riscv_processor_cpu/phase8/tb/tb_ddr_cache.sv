`timescale 1ns/1ps
module tb_ddr_cache #(parameter FAST=0);
    reg clk=0, rst_n=0, invalidate=0;
    always #5 clk=~clk;
    reg req_valid=0, req_write=0, rsp_ready=0;
    reg [31:0] req_addr=0, req_wdata=0;
    reg [3:0] req_wstrb=0;
    reg [1:0] req_size=2;
    wire req_ready, rsp_valid, rsp_err;
    wire [31:0] rsp_rdata;
    wire mv,mw,mrr;
    wire [31:0] ma,md;
    wire [3:0] ms;
    wire [1:0] mz;
    reg mr=0, rv=0, re=0;
    reg [31:0] rd=0;
    reg [7:0] memory[0:65535];
    reg pending=0, saved_write, inject_error=0, saved_error;
    reg [31:0] saved_addr,saved_data;
    reg [3:0] saved_strobes;
    reg [1:0] saved_size;
    integer delay_left=0, cycles=0, transfers=0, before_count, i;
    integer started, miss_cycles, hit_cycles;
    integer seed=27, offset, width;
    reg [31:0] value, expected;
    rv_ddr_cache #(.FAST_HIT(FAST)) dut(.clk(clk),.rst_n(rst_n),.invalidate(invalidate),
        .req_valid(req_valid),.req_ready(req_ready),.req_addr(req_addr),
        .req_wdata(req_wdata),.req_write(req_write),.req_wstrb(req_wstrb),.req_size(req_size),
        .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_rdata(rsp_rdata),.rsp_err(rsp_err),
        .mem_req_valid(mv),.mem_req_ready(mr),.mem_req_addr(ma),.mem_req_wdata(md),
        .mem_req_write(mw),.mem_req_wstrb(ms),.mem_req_size(mz),
        .mem_rsp_valid(rv),.mem_rsp_ready(mrr),.mem_rsp_rdata(rd),.mem_rsp_err(re));
    function automatic [31:0] mem_read(input [31:0] address, input [1:0] size);
        reg [31:0] v;
        begin
            v=0;
            for(integer b=0;b<(1<<size);b=b+1)
                v[b*8+:8]=memory[(address+b)&65535];
            mem_read=v;
        end
    endfunction
    always @(negedge clk) mr = rst_n && !pending && cycles%4==0;
    always @(posedge clk) if(rst_n) begin
        cycles<=cycles+1;
        if(mv && mr) begin
            pending<=1; saved_addr<=ma; saved_data<=md;
            saved_write<=mw; saved_strobes<=ms; saved_size<=mz;
            saved_error<=inject_error; delay_left<=3+cycles%5;
            transfers<=transfers+1;
        end
        if(pending && !rv) begin
            if(delay_left!=0) delay_left<=delay_left-1;
            else begin
                rv<=1; re<=saved_error || saved_size==3;
                rd<=saved_size==3 ? 0 : mem_read(saved_addr,saved_size);
                // An errored write may already have partially reached DDR.
                if(saved_write && saved_size!=3)
                    for(integer b=0;b<4;b=b+1)
                        if(saved_strobes[b]) memory[(saved_addr+b)&65535]<=saved_data[b*8+:8];
            end
        end
        if(rv && mrr) begin rv<=0; pending<=0; end
        if(cycles>100000) $fatal(1,"timeout");
    end
    // Check request stability while blocked at the backing port.
    reg held=0;
    reg [70:0] held_request;
    always @(posedge clk) if(rst_n) begin
        if(held && {ma,md,mw,ms,mz} !== held_request)
            $fatal(1,"backpressured request changed");
        held <= mv && !mr;
        held_request <= {ma,md,mw,ms,mz};
    end
    task automatic access(input [31:0] address, input wr, input [1:0] size,
        input [31:0] data_in, input [3:0] strobes, input [31:0] want,
        input error_expected, input flush_inflight);
        reg [31:0] held_data;
        reg held_err;
        begin
            @(negedge clk);
            req_addr=address; req_write=wr; req_size=size;
            req_wdata=data_in; req_wstrb=strobes; req_valid=1;
            do @(posedge clk); while(!req_ready);
            @(negedge clk); req_valid=0;
            if(flush_inflight) begin
                wait(pending); @(negedge clk); invalidate=1;
                @(negedge clk); invalidate=0;
            end
            wait(rsp_valid); #1;
            if(rsp_err !== error_expected || (!wr && !error_expected && rsp_rdata !== want))
                $fatal(1,"addr=%h wr=%b size=%d want=%h got=%h err=%b",address,wr,size,want,rsp_rdata,rsp_err);
            held_data=rsp_rdata; held_err=rsp_err;
            repeat(3) begin
                @(posedge clk); #1;
                if(!rsp_valid || rsp_rdata !== held_data || rsp_err !== held_err)
                    $fatal(1,"response changed under backpressure");
            end
            @(negedge clk); rsp_ready=1;
            @(negedge clk); rsp_ready=0;
        end
    endtask
    task automatic read_at(input [31:0] address,input [1:0] size);
        access(address,0,size,0,0,mem_read(address,size),0,0);
    endtask
    initial begin
        for(i=0;i<65536;i=i+1) memory[i]=(i*17+3)&255;
        repeat(3) @(negedge clk); rst_n=1;
        started=cycles;
        read_at('h80000000,2);
        miss_cycles=cycles-started;
        started=cycles;
        read_at('h80000000,2);
        hit_cycles=cycles-started;
        if(hit_cycles>=miss_cycles) $fatal(1,"hit not faster than miss");
        before_count=transfers;
        for(i=0;i<4;i=i+1) read_at('h80000000+i,0);
        read_at('h80000001,1);
        if(transfers!=before_count) $fatal(1,"narrow reads did not hit");
        access('h80000001,1,0,'hab,1,0,0,0);
        before_count=transfers; read_at('h80000000,2);
        if(transfers!=before_count) $fatal(1,"write hit not retained");
        access('h80000001,1,1,'h1234,3,0,0,0);
        read_at('h80000000,2);
        access('h80000000,1,2,'hfedcba98,5,0,0,0);
        read_at('h80000000,2);
        access('h80000000,1,2,0,0,0,0,0);
        read_at('h80000000,2);
        // Write misses reach memory but do not allocate a new line.
        access('h80000500,1,2,'h12345678,15,0,0,0);
        before_count=transfers; read_at('h80000500,2);
        if(transfers!=before_count+1) $fatal(1,"write miss unexpectedly allocated");
        // Conflicting tag, then original address must miss.
        read_at('h80002000,2); before_count=transfers;
        read_at('h80000000,2);
        if(transfers!=before_count+1) $fatal(1,"conflict not detected");
        // Cross-word writes invalidate both previously warm words.
        read_at('h80000004,2);
        access('h80000003,1,2,'h87654321,15,0,0,0);
        read_at('h80000000,2); read_at('h80000004,2); read_at('h80000003,2);
        // Out-of-range (e.g. MMIO) reads always bypass.
        before_count=transfers; read_at('h10000000,2); read_at('h10000000,2);
        if(transfers!=before_count+2) $fatal(1,"MMIO cached");
        // Read error, errored write, and invalidation during refill.
        inject_error=1;
        access('h80000100,0,2,0,0,0,1,0);
        inject_error=0; before_count=transfers; read_at('h80000100,2);
        if(transfers!=before_count+1) $fatal(1,"errored read allocated");
        inject_error=1;
        access('h80000100,1,2,'hdeadbeef,15,0,1,0);
        inject_error=0; before_count=transfers; read_at('h80000100,2);
        if(transfers!=before_count+1) $fatal(1,"errored write retained stale line");
        access('h80000300,0,2,0,0,mem_read('h300,2),0,1);
        before_count=transfers; read_at('h80000300,2);
        if(transfers!=before_count+1) $fatal(1,"invalidated refill allocated");
        access('h80000400,0,3,0,0,0,1,0);
        // Last word and a read outside the configured DDR window.
        read_at('h8fffffff,0);
        read_at('h8ffffffe,1);
        before_count=transfers;
        read_at('h90000000,2); read_at('h90000000,2);
        if(transfers!=before_count+2) $fatal(1,"out-of-range read cached");
        for(i=0;i<400;i=i+1) begin
            offset=($random(seed)&'h7fffffff)%16380;
            width=($random(seed)&'h7fffffff)%3;
            value=$random(seed);
            read_at('h80000000+offset,width);
            access('h80000000+offset,1,width,value,(1<<(1<<width))-1,0,0,0);
            read_at('h80000000+offset,width);
        end
        // Populate all 2048 lines and verify they coexist without refetches.
        for(i=0;i<8192;i=i+4) read_at('h80004000+i,2);
        before_count=transfers;
        for(i=0;i<8192;i=i+4) read_at('h80004000+i,2);
        if(transfers!=before_count) $fatal(1,"8 KiB capacity test failed");
        @(negedge clk); rst_n=0;
        repeat(3) @(negedge clk); rst_n=1;
        before_count=transfers; read_at('h80004000,2);
        if(transfers!=before_count+1) $fatal(1,"reset retained cache");
        $display("PASS DDR cache: 8 KiB capacity, partial stores, conflicts, bypass, errors, reset, inflight invalidate, backpressure, random scoreboard");
        $display("CACHE UNIT LATENCY including test backpressure: cold=%0d cycles warm=%0d cycles",miss_cycles,hit_cycles);
        $finish;
    end
endmodule
