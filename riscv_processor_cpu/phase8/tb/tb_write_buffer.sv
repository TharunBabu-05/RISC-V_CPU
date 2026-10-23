`timescale 1ns/1ps
module tb_write_buffer;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg req_valid=0,req_write=0,rsp_ready=0;
    reg [31:0] req_addr=0,req_wdata=0;
    reg [3:0] req_wstrb=0;
    reg [1:0] req_size=2;
    wire req_ready,rsp_valid,rsp_err;
    wire [31:0] rsp_rdata;
    wire mem_req_valid,mem_req_write,mem_rsp_ready,idle,fault;
    wire [31:0] mem_req_addr,mem_req_wdata,fault_addr;
    wire [3:0] mem_req_wstrb;
    wire [1:0] mem_req_size;
    wire mem_req_ready;
    reg mem_rsp_valid=0,mem_rsp_err=0;
    reg [31:0] mem_rsp_rdata=0;
    reg hold_memory=0,pending=0;
    reg [31:0] saved_addr,saved_data;
    reg saved_write;
    reg [3:0] saved_strobes;
    reg [1:0] saved_size;
    reg [7:0] memory[0:4095];
    reg [70:0] expected[0:2047];
    integer enqueued=0,issued=0,completed=0,cycles=0,delay_left=0,full_cycles=0;
    integer overlap=0,seed=17;
    reg stalled=0;
    reg [70:0] held_request;
    wire [70:0] outgoing={mem_req_addr,mem_req_wdata,mem_req_write,mem_req_wstrb,mem_req_size};
    rv_write_buffer dut(.*);
    assign mem_req_ready=rst_n && !pending && !hold_memory && cycles%3!=0;
    function automatic [31:0] read_value(input [31:0] addr,input [1:0] size);
        reg [31:0] v;
        begin
            v=0;
            for(integer b=0;b<(1<<size);b=b+1) v[b*8+:8]=memory[(addr+b)&4095];
            read_value=v;
        end
    endfunction
    always @(posedge clk) if(rst_n) begin
        cycles<=cycles+1;
        if(dut.count==4 && req_valid && !req_ready) full_cycles<=full_cycles+1;
        if(dut.push && dut.pop) overlap<=overlap+1;
        if(req_valid && req_ready && !fault) begin
            expected[enqueued]<={req_addr,req_wdata,req_write,req_wstrb,req_size};
            enqueued<=enqueued+1;
        end
        if(stalled && (!mem_req_valid || outgoing!==held_request)) $fatal(1,"request changed under backpressure");
        stalled<=mem_req_valid && !mem_req_ready;
        held_request<=outgoing;
        if(mem_req_valid && mem_req_ready) begin
            if(issued>=enqueued || outgoing!==expected[issued]) $fatal(1,"lost/reordered write %0d",issued);
            issued<=issued+1;
            pending<=1; saved_addr<=mem_req_addr; saved_data<=mem_req_wdata;
            saved_write<=mem_req_write; saved_strobes<=mem_req_wstrb; saved_size<=mem_req_size;
            delay_left<=cycles%11+5;
        end
        if(pending && !mem_rsp_valid) begin
            if(delay_left!=0) delay_left<=delay_left-1;
            else begin
                mem_rsp_valid<=1; mem_rsp_err<=saved_addr==32'h80000ffc || saved_addr==32'h90000000;
                mem_rsp_rdata<=read_value(saved_addr,saved_size);
                if(saved_write && saved_addr!=32'h80000ffc)
                    for(integer b=0;b<4;b=b+1)
                        if(saved_strobes[b]) memory[(saved_addr+b)&4095]<=saved_data[b*8+:8];
            end
        end
        if(mem_rsp_valid && mem_rsp_ready) begin
            mem_rsp_valid<=0; pending<=0; completed<=completed+1;
        end
    end
    task automatic access(input bit wr,input [31:0] addr,value,input [3:0] strobe,input [1:0] size,input bit err);
        reg [31:0] held;
        begin
            @(negedge clk); req_valid=1; req_addr=addr; req_write=wr;
            req_wdata=value; req_wstrb=strobe; req_size=size;
            do @(posedge clk); while(!req_ready);
            @(negedge clk); req_valid=0;
            wait(rsp_valid); #1;
            if(rsp_err!==err) $fatal(1,"response error addr=%h expected=%b",addr,err);
            if(!wr && !err && rsp_rdata!==read_value(addr,size)) $fatal(1,"read passed older stores");
            held=rsp_rdata;
            repeat(3) begin
                @(negedge clk);
                if(!rsp_valid || rsp_rdata!==held || rsp_err!==err) $fatal(1,"unstable response");
            end
            rsp_ready=1;
            @(negedge clk); rsp_ready=0;
        end
    endtask
    initial begin
        for(integer n=0;n<4096;n=n+1) memory[n]=0;
        repeat(3) @(negedge clk); rst_n=1; hold_memory=1;
        for(integer n=0;n<4;n=n+1) access(1,32'h80000000+n*4,n+10,15,2,0);
        if(completed!=0 || dut.count!=4) $fatal(1,"writes were not posted");
        fork
            access(1,32'h80000010,14,15,2,0);
            begin repeat(12) @(negedge clk); hold_memory=0; end
        join
        access(0,32'h80000000,0,0,2,0);
        if(full_cycles==0) $fatal(1,"full queue untested");
        access(1,32'h80000001,32'hcc,1,0,0);
        access(1,32'h80000002,32'habcd,3,1,0);
        access(0,32'h80000001,0,0,0,0);
        access(0,32'h80000002,0,0,1,0);
        for(integer n=0;n<300;n=n+1) begin
            access(1,32'h80000100+(n%8),$random(seed),n%16,2,0);
            if(n%7==0) access(0,32'h80000100+(n%8),0,0,2,0);
        end
        // MMIO is a drain barrier; it cannot pass pending DDR stores.
        access(1,32'h10000000,32'habcdef01,15,2,0);
        if(completed!=enqueued) $fatal(1,"MMIO did not drain");
        access(1,32'h80000200,123,15,2,0);
        wait(mem_rsp_valid && dut.state==2);
        access(1,32'h80000204,456,15,2,0);
        access(0,32'h80000204,0,0,2,0);
        if(overlap==0) $fatal(1,"simultaneous push/pop untested");
        access(0,32'h90000000,0,0,2,1);
        if(fault) $fatal(1,"direct error incorrectly latched as delayed store error");
        access(1,32'h80000ffc,32'hbad,15,2,0);
        wait(fault); #1;
        if(fault_addr!==32'h80000ffc || mem_req_valid) $fatal(1,"delayed failure not latched");
        access(0,32'h80000000,0,0,2,1);
        @(negedge clk); rst_n=0;
        repeat(3) @(negedge clk); rst_n=1;
        if(fault || !idle) $fatal(1,"reset did not recover buffer");
        access(0,32'h80000000,0,0,2,0);
        $display("PASS write buffer: FIFO/partial stores/full queue/read+MMIO drain/backpressure/errors/reset (%0d requests, %0d simultaneous push/pop)",issued,overlap);
        $finish;
    end
    initial begin #500000; $fatal(1,"write buffer timeout"); end
endmodule
