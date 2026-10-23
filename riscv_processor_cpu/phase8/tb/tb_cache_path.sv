`timescale 1ns/1ps
module tb_cache_path #(parameter LOCAL=1, POSTED=1);
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [31:0] addr=0,wdata=0;
    reg ren=0,wen=0;
    wire ev,ew,er,erv,err,ers;
    wire [31:0] ea,ed,erd;
    wire [3:0] es,status;
    wire [1:0] ez;
    reg pending=0,rv=0;
    reg [31:0] saved_addr,saved_data,result;
    reg saved_write;
    reg [3:0] saved_strobes;
    integer cycles=0,left=0,reads=0,writes=0;
    reg [7:0] memory[0:4095];
    soc_core #(.FIRMWARE_FILE(""),.ENABLE_EXT_MEM(1),.ENABLE_DCACHE(1),
        .LOCAL_DCACHE(LOCAL),.BUFFER_WRITES(POSTED)) dut(
        .clk_sys(clk),.rst_n(rst_n),.uart_rx(1'b1),.qspi_dq1_i(1'b0),.status(status),
        .ext_mem_ready(1'b1),.ext_req_valid(ev),.ext_req_ready(er),.ext_req_addr(ea),
        .ext_req_write(ew),.ext_req_wstrb(es),.ext_req_wdata(ed),.ext_req_size(ez),
        .ext_rsp_valid(erv),.ext_rsp_ready(ers),.ext_rsp_rdata(erd),.ext_rsp_err(err),
        .sim_bus_override(1'b1),.sim_bus_addr(addr),.sim_bus_wdata(wdata),
        .sim_bus_rd_en(ren),.sim_bus_wr_en(wen),.sim_bus_funct3(3'b010),.sim_irq_sources(4'b0));
    assign er=!pending && cycles%3!=0;
    assign erv=rv;
    assign erd=result;
    assign err=rv && saved_addr==32'h80000ffc;
    always @(posedge clk) if(rst_n) begin
        cycles<=cycles+1;
        if(ev && er) begin
            pending<=1; saved_addr<=ea; saved_data<=ed; saved_write<=ew;
            saved_strobes<=es; left<=12;
            if(ew) writes<=writes+1; else reads<=reads+1;
        end
        if(pending && !rv) begin
            if(left!=0) left<=left-1;
            else begin
                rv<=1;
                for(integer b=0;b<4;b=b+1) begin
                    result[b*8+:8]<=memory[(saved_addr+b)&4095];
                    if(saved_write && saved_strobes[b] && saved_addr!=32'h80000ffc)
                        memory[(saved_addr+b)&4095]<=saved_data[b*8+:8];
                end
            end
        end
        if(rv && ers) begin rv<=0; pending<=0; end
        if(LOCAL && dut.dma_req_valid && dut.dma_req_ready && (!dut.cache_idle || !dut.buffer_idle))
            $fatal(1,"DMA crossed undrained CPU writes");
    end
    integer elapsed;
    reg [31:0] value;
    task automatic access(input bit wr,input [31:0] a,d,input bit expect_error);
        integer start;
        begin
            @(negedge clk); addr=a; wdata=d; wen=wr; ren=!wr; start=cycles;
            do @(posedge clk); while(!dut.host_req_ready);
            @(negedge clk); wen=0; ren=0;
            wait(dut.sim_rsp_valid); #1;
            if(dut.sim_rsp_err!==expect_error) $fatal(1,"host error at %h",a);
            value=dut.sim_rsp_rdata; elapsed=cycles-start;
        end
    endtask
    task automatic read_check(input [31:0] a,d);
        access(0,a,0,0);
        if(value!==d) $fatal(1,"stale data addr=%h expected=%h actual=%h",a,d,value);
    endtask
    task automatic dma_copy(input [31:0] src,dst);
        access(1,32'h10002010,7,0);
        access(1,32'h10002000,src,0);
        access(1,32'h10002004,dst,0);
        access(1,32'h10002008,4,0);
        access(1,32'h1000200c,32'h37,0);
        wait(dut.u_dma.busy);
        wait(!dut.u_dma.busy);
    endtask
    integer cold,hit,start,store_cycles,old_reads;
    initial begin
        // Keep the CPU in its TCM while the host exercises its actual data port.
        force dut.cpu_imem_rdata=32'h0000006f;
        for(integer n=0;n<4096;n=n+1) memory[n]=0;
        repeat(5) @(negedge clk); rst_n=1;
        read_check(32'h80000000,0); cold=elapsed; old_reads=reads;
        read_check(32'h80000000,0); hit=elapsed;
        if(reads!=old_reads || hit>=cold) $fatal(1,"no cache hit");
        start=cycles;
        for(integer n=0;n<16;n=n+1) access(1,32'h80000000,n+1,0);
        store_cycles=cycles-start;
        read_check(32'h80000000,16);
        access(1,32'h80000004,32'h11223344,0);
        dma_copy(32'h80000004,32'h80000000);
        read_check(32'h80000000,32'h11223344);
        access(1,32'h80000000,32'habcdef01,0);
        dma_copy(32'h80000000,32'h80000008);
        read_check(32'h80000008,32'habcdef01);
        if(LOCAL) begin
            access(1,32'h80000000,32'h76543210,0);
            @(negedge clk);
            force dut.cpu_i_req_valid=1; force dut.cpu_i_req_addr=32'h80000000;
            force dut.cpu_i_rsp_ready=1;
            do @(posedge clk); while(!dut.cpu_i_req_ready);
            if(!dut.buffer_idle) $fatal(1,"instruction refill crossed posted store");
            @(negedge clk); force dut.cpu_i_req_valid=0;
            wait(dut.cpu_i_rsp_valid); #1;
            if(dut.cpu_i_rsp_rdata!==32'h76543210) $fatal(1,"instruction fill saw stale store");
            @(posedge clk); @(negedge clk);
            release dut.cpu_i_req_valid; release dut.cpu_i_req_addr; release dut.cpu_i_rsp_ready;
            // A page-table walker is another coherent master, including writes.
            @(negedge clk);
            force dut.ptw_req_valid=1; force dut.ptw_req_addr=32'h80000000;
            force dut.ptw_req_write=1; force dut.ptw_req_wdata=32'h12345678;
            force dut.ptw_req_wstrb=15; force dut.ptw_req_size=2;
            force dut.ptw_rsp_ready=1;
            do @(posedge clk); while(!dut.ptw_req_ready);
            @(negedge clk); force dut.ptw_req_valid=0;
            wait(dut.ptw_rsp_valid); @(posedge clk); @(negedge clk);
            release dut.ptw_req_valid; release dut.ptw_req_addr; release dut.ptw_req_write;
            release dut.ptw_req_wdata; release dut.ptw_req_wstrb; release dut.ptw_req_size;
            release dut.ptw_rsp_ready;
            read_check(32'h80000000,32'h12345678);
        end
        if(LOCAL && POSTED) begin
            access(1,32'h80000ffc,32'hbad,0);
            wait(dut.buffer_fault); #1;
            if(status[1]!==0 || dut.buffer_fault_addr!==32'h80000ffc) $fatal(1,"missing fail-stop status");
            @(negedge clk); ren=1; addr=32'h80000000;
            repeat(10) begin
                @(posedge clk);
                if(dut.host_req_ready || dut.host_rsp_valid || ev) $fatal(1,"CPU/DMA continued after posted error");
            end
        end
        $display("PASS cache path local=%0d posted=%0d cold=%0d hit=%0d cycles, 16 stores=%0d cycles; DMA/PTW coherence",LOCAL,POSTED,cold,hit,store_cycles);
        $finish;
    end
    initial begin #1000000; $fatal(1,"cache path timeout pc=%h",dut.u_cpu.pc); end
endmodule
