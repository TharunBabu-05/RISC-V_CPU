`timescale 1ns/1ps
module tb_ddr_soc #(
    parameter LOADER_MODE=0,
    parameter FIRMWARE_FILE="../software/build/ddr_test.vmem"
);
    reg clk=0, rst_n=0, memory_ready=0, uart_rx=1;
    always #20 clk=~clk;
    wire req_valid, req_ready, req_write, rsp_valid, rsp_ready, rsp_err;
    wire [31:0] req_addr, req_wdata, rsp_rdata;
    wire [3:0] req_wstrb, status;
    wire [1:0] req_size;
    wire uart_tx;
    integer external_fetches=0, local_fetches=0, fast_run=0, longest_fast_run=0;
    integer trace_cycles=0;
    reg [31:0] previous_pc=0;
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
    soc_core #(.FIRMWARE_FILE(FIRMWARE_FILE),
               .ENABLE_EXT_MEM(1), .UART_BAUD(2500000)) dut (
        .clk_sys(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .qspi_dq1_i(1'b1), .status(status),
        .sim_bus_override(1'b0), .sim_bus_addr(32'b0), .sim_bus_wdata(32'b0),
        .sim_bus_rd_en(1'b0), .sim_bus_wr_en(1'b0), .sim_bus_funct3(3'b010),
        .sim_irq_sources(4'b0),
        .ext_mem_ready(memory_ready), .ext_req_valid(req_valid), .ext_req_ready(req_ready),
        .ext_req_addr(req_addr), .ext_req_write(req_write), .ext_req_wstrb(req_wstrb),
        .ext_req_wdata(req_wdata), .ext_req_size(req_size),
        .ext_rsp_valid(rsp_valid), .ext_rsp_ready(rsp_ready),
        .ext_rsp_rdata(rsp_rdata), .ext_rsp_err(rsp_err)
    );
    rv_bus_to_axi128 bridge (
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
        .inject_read_error(1'b0), .inject_write_error(1'b0),
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
    string good="DDR:PASS", bad="DDR:FAIL", trap="DDR:TRAP";
    integer good_pos=0, bad_pos=0, trap_pos=0;
    reg [7:0] ch;
    reg [7:0] image [0:4095];
    integer image_fd, image_size;
    reg [31:0] crc;
    string loader_line="";
    reg upload_verified=0, info_verified=0;
    task automatic send_uart(input reg [7:0] value);
        @(negedge clk); uart_rx=0;
        repeat (10) @(negedge clk);
        for (integer bit_index=0; bit_index<8; bit_index=bit_index+1) begin
            uart_rx=value[bit_index];
            repeat (10) @(negedge clk);
        end
        uart_rx=1;
        repeat (10) @(negedge clk);
    endtask
    initial if (LOADER_MODE) begin
        good="DDR_APP:PASS";
        image_fd=$fopen("../software/build/ddr_app_test.bin", "rb");
        if (!image_fd) $fatal(1,"Missing DDR test app binary");
        image_size=$fread(image,image_fd);
        $fclose(image_fd);
        if (image_size < 1 || image_size > 4096) $fatal(1,"Bad DDR test app size");
        crc=32'hffffffff;
        for (integer i=0; i<image_size; i=i+1) begin
            crc=crc ^ image[i];
            for (integer j=0; j<8; j=j+1)
                crc=(crc >> 1) ^ ((crc[0]) ? 32'hedb88320 : 0);
        end
        crc=crc ^ 32'hffffffff;
        wait(memory_ready);
        repeat (10000) @(negedge clk);
        send_uart($test$plusargs("DEFERRED_RUN") ? "U" : "A");
        repeat (3000) @(negedge clk);
        send_uart("R"); send_uart("D"); send_uart("D"); send_uart("1");
        for (integer i=0; i<4; i=i+1) send_uart((image_size >> (8*i)) & 8'hff);
        for (integer i=0; i<4; i=i+1) send_uart((crc >> (8*i)) & 8'hff);
        repeat (3000) @(negedge clk);
        for (integer i=0; i<image_size; i=i+1) begin
            send_uart(image[i]);
            if (((i+1) % 16) == 0 || i+1 == image_size)
                repeat (2500) @(negedge clk);
        end
        if ($test$plusargs("DEFERRED_RUN")) begin
            wait(upload_verified);
            // Model the idle interval while the host releases the serial port.
            repeat (10000) @(negedge clk);
            send_uart("I");
            wait(info_verified);
            repeat (2000) @(negedge clk);
            send_uart("G");
        end
    end
    always @(posedge clk) if(rst_n) begin
        trace_cycles <= trace_cycles+1;
        if ($test$plusargs("TRACE") && trace_cycles % 1000 == 0)
            $display("cycle=%d pc=%h inst=%h",trace_cycles,dut.u_cpu.pc,dut.u_cpu.if_instr);
        if(dut.cpu_i_req_valid && dut.cpu_i_req_ready) external_fetches <= external_fetches+1;
        if(dut.u_cpu.if_fast_local && dut.u_cpu.if_id_write && !dut.u_cpu.flush_if_id) begin
            local_fetches <= local_fetches+1;
            if(dut.u_cpu.pc == previous_pc+4) fast_run <= fast_run+1;
            else fast_run <= 1;
        end else fast_run <= 0;
        previous_pc <= dut.u_cpu.pc;
        if(fast_run > longest_fast_run) longest_fast_run <= fast_run;
        if(dut.u_uart.tx_valid) begin
            ch=dut.u_uart.tx_data; $write("%c",ch);
            if (LOADER_MODE) begin
                if (ch == 10) begin
                    if (loader_line == "RDD1:OK") upload_verified=1;
                    if (loader_line == $sformatf("RDD1:INFO BASE=80000000 MAX=4194304 LOADED=%0d", image_size))
                        info_verified=1;
                    if (loader_line == "RDD1:ERR NO_IMAGE")
                        $fatal(1,"Loader lost verified image before G");
                    loader_line="";
                end else if (ch != 13) loader_line={loader_line,ch};
            end
            good_pos=(ch == good[good_pos]) ? good_pos+1 : (ch == good[0] ? 1 : 0);
            bad_pos=(ch == bad[bad_pos]) ? bad_pos+1 : (ch == bad[0] ? 1 : 0);
            trap_pos=(ch == trap[trap_pos]) ? trap_pos+1 : (ch == trap[0] ? 1 : 0);
            if(bad_pos == bad.len() || trap_pos == trap.len())
                $fatal(1,"DDR firmware reported failure");
            if(good_pos == good.len()) begin
                if (LOADER_MODE && $test$plusargs("DEFERRED_RUN") && !info_verified)
                    $fatal(1,"Application ran without confirming retained image state");
                if(external_fetches < (LOADER_MODE ? 1 : 50) || local_fetches < 100 || longest_fast_run < 8)
                    $fatal(1,"Missing mixed execution or one-instruction-per-cycle TCM evidence");
                $display("\nPASS: DDR firmware + CPU + DMA + AXI; external fetches=%0d local=%0d consecutive TCM=%0d",
                    external_fetches,local_fetches,longest_fast_run);
                $finish;
            end
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        repeat(20000) @(negedge clk); memory_ready=1;
    end
    initial begin
        #400000000;
        $fatal(1,"DDR SoC timeout pc=%h inst=%h fetch=%b pending=%b killed=%b req=%b rsp=%b",
            dut.u_cpu.pc,dut.u_cpu.if_instr,dut.u_cpu.ifetch_valid,dut.u_cpu.ifetch_pending,
            dut.u_cpu.ifetch_killed,req_valid,rsp_valid);
    end
endmodule

