`timescale 1ns/1ps
module tb_axi128;
    reg clk=0, rst_n=0, memory_ready=0;
    always #5 clk=~clk;
    reg req_valid=0, req_write=0, rsp_ready=0;
    wire req_ready, rsp_valid, rsp_err;
    reg [31:0] req_addr=0, req_wdata=0;
    reg [3:0] req_wstrb=0;
    reg [1:0] req_size=0;
    wire [31:0] rsp_rdata;
    reg inject_read_error=0, inject_write_error=0;
    wire [3:0] axi_awid;
    wire [27:0] axi_awaddr;
    wire [7:0] axi_awlen;
    wire [2:0] axi_awsize;
    wire [1:0] axi_awburst;
    wire axi_awlock;
    wire [3:0] axi_awcache;
    wire [2:0] axi_awprot;
    wire [3:0] axi_awqos;
    wire axi_awvalid;
    wire axi_awready;
    wire [127:0] axi_wdata;
    wire [15:0] axi_wstrb;
    wire axi_wlast;
    wire axi_wvalid;
    wire axi_wready;
    wire [3:0] axi_bid;
    wire [1:0] axi_bresp;
    wire axi_bvalid;
    wire axi_bready;
    wire [3:0] axi_arid;
    wire [27:0] axi_araddr;
    wire [7:0] axi_arlen;
    wire [2:0] axi_arsize;
    wire [1:0] axi_arburst;
    wire axi_arlock;
    wire [3:0] axi_arcache;
    wire [2:0] axi_arprot;
    wire [3:0] axi_arqos;
    wire axi_arvalid;
    wire axi_arready;
    wire [3:0] axi_rid;
    wire [127:0] axi_rdata;
    wire [1:0] axi_rresp;
    wire axi_rlast;
    wire axi_rvalid;
    wire axi_rready;
    rv_bus_to_axi128 dut (
        .clk(clk), .rst_n(rst_n), .memory_ready(memory_ready),
        .bus_req_valid(req_valid), .bus_req_ready(req_ready), .bus_req_addr(req_addr),
        .bus_req_wdata(req_wdata), .bus_req_write(req_write),
        .bus_req_wstrb(req_wstrb), .bus_req_size(req_size),
        .bus_rsp_valid(rsp_valid), .bus_rsp_ready(rsp_ready),
        .bus_rsp_rdata(rsp_rdata), .bus_rsp_err(rsp_err),
        .m_axi_awid(axi_awid),
        .m_axi_awaddr(axi_awaddr),
        .m_axi_awlen(axi_awlen),
        .m_axi_awsize(axi_awsize),
        .m_axi_awburst(axi_awburst),
        .m_axi_awlock(axi_awlock),
        .m_axi_awcache(axi_awcache),
        .m_axi_awprot(axi_awprot),
        .m_axi_awqos(axi_awqos),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata),
        .m_axi_wstrb(axi_wstrb),
        .m_axi_wlast(axi_wlast),
        .m_axi_wvalid(axi_wvalid),
        .m_axi_wready(axi_wready),
        .m_axi_bid(axi_bid),
        .m_axi_bresp(axi_bresp),
        .m_axi_bvalid(axi_bvalid),
        .m_axi_bready(axi_bready),
        .m_axi_arid(axi_arid),
        .m_axi_araddr(axi_araddr),
        .m_axi_arlen(axi_arlen),
        .m_axi_arsize(axi_arsize),
        .m_axi_arburst(axi_arburst),
        .m_axi_arlock(axi_arlock),
        .m_axi_arcache(axi_arcache),
        .m_axi_arprot(axi_arprot),
        .m_axi_arqos(axi_arqos),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arready),
        .m_axi_rid(axi_rid),
        .m_axi_rdata(axi_rdata),
        .m_axi_rresp(axi_rresp),
        .m_axi_rlast(axi_rlast),
        .m_axi_rvalid(axi_rvalid),
        .m_axi_rready(axi_rready)
    );
    axi128_ram_model ram (.clk(clk), .rst_n(rst_n),
        .inject_read_error(inject_read_error), .inject_write_error(inject_write_error),
        .axi_awid(axi_awid),
        .axi_awaddr(axi_awaddr),
        .axi_awlen(axi_awlen),
        .axi_awsize(axi_awsize),
        .axi_awburst(axi_awburst),
        .axi_awlock(axi_awlock),
        .axi_awcache(axi_awcache),
        .axi_awprot(axi_awprot),
        .axi_awqos(axi_awqos),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wlast(axi_wlast),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_bid(axi_bid),
        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_arid(axi_arid),
        .axi_araddr(axi_araddr),
        .axi_arlen(axi_arlen),
        .axi_arsize(axi_arsize),
        .axi_arburst(axi_arburst),
        .axi_arlock(axi_arlock),
        .axi_arcache(axi_arcache),
        .axi_arprot(axi_arprot),
        .axi_arqos(axi_arqos),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_rid(axi_rid),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready)
    );
    reg [7:0] expected [0:511];
    reg [31:0] result, word_expected, value, hold_data;
    reg hold_error;
    integer transactions=0, width, off, bytes, before_count;
    task automatic transfer(input bit wr, input [31:0] addr, input [31:0] data,
                            input [1:0] size, input [3:0] strb, input bit error_expected);
        begin
            @(negedge clk);
            req_valid=1; req_write=wr; req_addr=addr; req_wdata=data; req_size=size; req_wstrb=strb;
            do @(posedge clk); while (!req_ready);
            @(negedge clk); req_valid=0;
            wait(rsp_valid);
            hold_data=rsp_rdata; hold_error=rsp_err;
            repeat(4) begin
                @(negedge clk);
                if (!rsp_valid || rsp_rdata !== hold_data || rsp_err !== hold_error)
                    $fatal(1,"Response changed under backpressure");
            end
            if (rsp_err !== error_expected) $fatal(1,"Unexpected error addr=%h err=%b",addr,rsp_err);
            result=rsp_rdata; rsp_ready=1;
            @(negedge clk); rsp_ready=0;
            transactions=transactions+1;
        end
    endtask
    initial begin
        for(integer i=0;i<512;i=i+1) expected[i]=0;
        repeat(5) @(negedge clk); rst_n=1;
        transfer(0,32'h80000000,0,2,0,1);
        if (ram.read_count || ram.write_count) $fatal(1,"Access before calibration");
        memory_ready=1;
        for(width=0;width<3;width=width+1) begin
            bytes=1<<width;
            for(off=0;off<32;off=off+1) begin
                value=32'hD00DA55A ^ (off*32'h1020304);
                transfer(1,32'h80000000+off,value,width,(1<<bytes)-1,0);
                for(integer k=0;k<bytes;k=k+1) expected[off+k]=value>>(k*8);
                transfer(0,32'h80000000+off,0,width,0,0);
                word_expected=value & (32'hFFFFFFFF >> (32-bytes*8));
                if(result !== word_expected) $fatal(1,"Lane/crossing failure %d %d got %h want %h",width,off,result,word_expected);
            end
        end
        for(integer i=0;i<500;i=i+1) begin
            off=$urandom_range(0,480); width=$urandom_range(0,2); bytes=1<<width; value=$urandom;
            transfer(1,32'h80000000+off,value,width,(1<<bytes)-1,0);
            for(integer k=0;k<bytes;k=k+1) expected[off+k]=value>>(k*8);
            off=$urandom_range(0,480); word_expected=0;
            for(integer k=0;k<4;k=k+1) word_expected=word_expected | (32'(expected[off+k]) << (k*8));
            transfer(0,32'h80000000+off,0,2,0,0);
            if(result !== word_expected) $fatal(1,"Random readback mismatch %d: %h != %h",off,result,word_expected);
        end
        transfer(1,32'h8FFFFFFC,32'h13579BDF,2,15,0);
        transfer(0,32'h8FFFFFFC,0,2,0,0);
        if(result !== 32'h13579BDF) $fatal(1,"Last word mapping");
        before_count=ram.read_count+ram.write_count;
        transfer(1,32'h8FFFFFFE,32'hBAD,2,15,1);
        transfer(0,32'h90000000,0,2,0,1);
        transfer(0,32'h7FFFFFFF,0,0,0,1);
        transfer(1,32'h80000000,0,3,15,1);
        transfer(1,32'h80000000,0,0,2,1);
        if(before_count != ram.read_count+ram.write_count) $fatal(1,"Invalid access reached AXI");
        inject_read_error=1;
        transfer(0,32'h8000000F,0,2,0,1);
        inject_read_error=0; inject_write_error=1;
        transfer(1,32'h8000000F,0,2,15,1);
        inject_write_error=0;
        // Common reset aborts both sides, including a stalled write.
        @(negedge clk);
        force axi_wready=0;
        req_valid=1; req_write=1; req_addr=32'h80000020; req_size=2; req_wstrb=15;
        do @(posedge clk); while(!req_ready);
        @(negedge clk); req_valid=0;
        wait(axi_awvalid && axi_awready);
        @(negedge clk); rst_n=0;
        repeat(4) @(negedge clk);
        release axi_wready;
        rst_n=1;
        transfer(1,32'h80000020,32'hABCDEF01,2,15,0);
        transfer(0,32'h80000020,0,2,0,0);
        if(result !== 32'hABCDEF01) $fatal(1,"Reset recovery");
        $display("PASS: AXI128 %0d transactions: lanes, split beats, random stalls, errors, range, reset",transactions);
        $finish;
    end
    initial begin #5000000; $fatal(1,"AXI128 timeout"); end
endmodule

