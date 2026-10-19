// Separate Arty S7-50 DDR experiment; the existing soc_top remains the default.
// CDC uses AMD's AXI Clock Converter IP, not independent bit synchronizers.
`timescale 1ns/1ps
module arty_s7_ddr_top #(
    parameter FIRMWARE_FILE = "ddr_test.vmem",
    parameter integer UART_BAUD = 115200
) (
    input wire clk_12mhz, sys_clk_i, rst_btn,
    input wire uart_rx,
    output wire uart_tx, qspi_cs,
    inout wire [3:0] qspi_dq,
    output wire [3:0] led,
    inout wire [15:0] ddr3_dq,
    inout wire [1:0] ddr3_dqs_n, ddr3_dqs_p,
    output wire [13:0] ddr3_addr,
    output wire [2:0] ddr3_ba,
    output wire ddr3_ras_n, ddr3_cas_n, ddr3_we_n, ddr3_reset_n,
    output wire [0:0] ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_cs_n, ddr3_odt,
    output wire [1:0] ddr3_dm
);
    wire clk_sys, clk_ref, locked, ui_clk, ui_reset, calibrated;
    wire clock_reset_n = locked && !rst_btn;
    (* ASYNC_REG = "TRUE" *) reg [3:0] sys_reset_pipe = 0;
    (* ASYNC_REG = "TRUE" *) reg [3:0] ui_reset_pipe = 0;
    (* ASYNC_REG = "TRUE" *) reg [2:0] ready_pipe = 0;
    wire soc_rst_n = sys_reset_pipe[3];
    wire axi_reset_n = clock_reset_n && !ui_reset;
    wire ui_rst_n = ui_reset_pipe[3];
    (* ASYNC_REG = "TRUE" *) reg [3:0] axi_sys_reset_pipe = 0;
    wire axi_sys_rst_n = axi_sys_reset_pipe[3];
    wire memory_ready = ready_pipe[2] && axi_sys_rst_n;

    clk_wiz_0 u_pll (.clk_in1(clk_12mhz), .clk_out1(clk_sys),
                    .clk_out2(clk_ref), .locked(locked));
    always @(posedge clk_sys or negedge clock_reset_n)
        if (!clock_reset_n) sys_reset_pipe <= 0;
        else sys_reset_pipe <= {sys_reset_pipe[2:0], 1'b1};
    // Both sides of the converter share reset assertion. Release is local.
    // The TCM CPU stays alive during DDR calibration to print diagnostics.
    always @(posedge clk_sys or negedge axi_reset_n)
        if (!axi_reset_n) axi_sys_reset_pipe <= 0;
        else axi_sys_reset_pipe <= {axi_sys_reset_pipe[2:0], 1'b1};
    always @(posedge ui_clk or negedge axi_reset_n)
        if (!axi_reset_n) ui_reset_pipe <= 0;
        else ui_reset_pipe <= {ui_reset_pipe[2:0], 1'b1};
    always @(posedge clk_sys or negedge clock_reset_n)
        if (!clock_reset_n) ready_pipe <= 0;
        else ready_pipe <= {ready_pipe[1:0], calibrated && !ui_reset};

    wire req_valid, req_ready, req_write, rsp_valid, rsp_ready, rsp_err;
    wire [31:0] req_addr, req_wdata, rsp_rdata;
    wire [3:0] req_wstrb, status;
    wire [1:0] req_size;
    wire qspi_sck, dq0_o, dq0_oe;
    assign qspi_dq = {3'bzzz, dq0_oe ? dq0_o : 1'bz};
    STARTUPE2 u_startup (.CFGCLK(), .CFGMCLK(), .EOS(), .PREQ(),
        .CLK(1'b0), .GSR(1'b0), .GTS(1'b0), .KEYCLEARB(1'b1), .PACK(1'b0),
        .USRCCLKO(qspi_sck), .USRCCLKTS(1'b0),
        .USRDONEO(1'b1), .USRDONETS(1'b1));

    soc_core #(.FIRMWARE_FILE(FIRMWARE_FILE), .ENABLE_EXT_MEM(1'b1),
               .UART_BAUD(UART_BAUD)) u_soc (
        .clk_sys(clk_sys), .rst_n(soc_rst_n), .uart_tx(uart_tx), .uart_rx(uart_rx),
        .qspi_cs(qspi_cs), .qspi_sck(qspi_sck), .qspi_dq0_o(dq0_o),
        .qspi_dq0_oe(dq0_oe), .qspi_dq1_i(qspi_dq[1]), .status(status),
        .ext_mem_ready(memory_ready), .ext_req_valid(req_valid),
        .ext_req_ready(req_ready), .ext_req_addr(req_addr), .ext_req_write(req_write),
        .ext_req_wstrb(req_wstrb), .ext_req_wdata(req_wdata), .ext_req_size(req_size),
        .ext_rsp_valid(rsp_valid), .ext_rsp_ready(rsp_ready),
        .ext_rsp_rdata(rsp_rdata), .ext_rsp_err(rsp_err)
    );

    wire [3:0] s_awid;
    wire [27:0] s_awaddr;
    wire [7:0] s_awlen;
    wire [2:0] s_awsize;
    wire [1:0] s_awburst;
    wire s_awlock;
    wire [3:0] s_awcache;
    wire [2:0] s_awprot;
    wire [3:0] s_awqos;
    wire s_awvalid;
    wire s_awready;
    wire [127:0] s_wdata;
    wire [15:0] s_wstrb;
    wire s_wlast;
    wire s_wvalid;
    wire s_wready;
    wire [3:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    wire s_bready;
    wire [3:0] s_arid;
    wire [27:0] s_araddr;
    wire [7:0] s_arlen;
    wire [2:0] s_arsize;
    wire [1:0] s_arburst;
    wire s_arlock;
    wire [3:0] s_arcache;
    wire [2:0] s_arprot;
    wire [3:0] s_arqos;
    wire s_arvalid;
    wire s_arready;
    wire [3:0] s_rid;
    wire [127:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    wire s_rready;
    wire [3:0] m_awid;
    wire [27:0] m_awaddr;
    wire [7:0] m_awlen;
    wire [2:0] m_awsize;
    wire [1:0] m_awburst;
    wire m_awlock;
    wire [3:0] m_awcache;
    wire [2:0] m_awprot;
    wire [3:0] m_awqos;
    wire m_awvalid;
    wire m_awready;
    wire [127:0] m_wdata;
    wire [15:0] m_wstrb;
    wire m_wlast;
    wire m_wvalid;
    wire m_wready;
    wire [3:0] m_bid;
    wire [1:0] m_bresp;
    wire m_bvalid;
    wire m_bready;
    wire [3:0] m_arid;
    wire [27:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire m_arlock;
    wire [3:0] m_arcache;
    wire [2:0] m_arprot;
    wire [3:0] m_arqos;
    wire m_arvalid;
    wire m_arready;
    wire [3:0] m_rid;
    wire [127:0] m_rdata;
    wire [1:0] m_rresp;
    wire m_rlast;
    wire m_rvalid;
    wire m_rready;
    // The bridge shares the CPU reset. An unexpected MIG reset during an
    // outstanding transfer requires BTN0: AXI has no transaction cancellation.
    rv_bus_to_axi128 u_bridge (
        .clk(clk_sys), .rst_n(soc_rst_n), .memory_ready(memory_ready),
        .bus_req_valid(req_valid), .bus_req_ready(req_ready), .bus_req_addr(req_addr),
        .bus_req_wdata(req_wdata), .bus_req_write(req_write),
        .bus_req_wstrb(req_wstrb), .bus_req_size(req_size),
        .bus_rsp_valid(rsp_valid), .bus_rsp_ready(rsp_ready),
        .bus_rsp_rdata(rsp_rdata), .bus_rsp_err(rsp_err),
        .m_axi_awid(s_awid),
        .m_axi_awaddr(s_awaddr),
        .m_axi_awlen(s_awlen),
        .m_axi_awsize(s_awsize),
        .m_axi_awburst(s_awburst),
        .m_axi_awlock(s_awlock),
        .m_axi_awcache(s_awcache),
        .m_axi_awprot(s_awprot),
        .m_axi_awqos(s_awqos),
        .m_axi_awvalid(s_awvalid),
        .m_axi_awready(s_awready),
        .m_axi_wdata(s_wdata),
        .m_axi_wstrb(s_wstrb),
        .m_axi_wlast(s_wlast),
        .m_axi_wvalid(s_wvalid),
        .m_axi_wready(s_wready),
        .m_axi_bid(s_bid),
        .m_axi_bresp(s_bresp),
        .m_axi_bvalid(s_bvalid),
        .m_axi_bready(s_bready),
        .m_axi_arid(s_arid),
        .m_axi_araddr(s_araddr),
        .m_axi_arlen(s_arlen),
        .m_axi_arsize(s_arsize),
        .m_axi_arburst(s_arburst),
        .m_axi_arlock(s_arlock),
        .m_axi_arcache(s_arcache),
        .m_axi_arprot(s_arprot),
        .m_axi_arqos(s_arqos),
        .m_axi_arvalid(s_arvalid),
        .m_axi_arready(s_arready),
        .m_axi_rid(s_rid),
        .m_axi_rdata(s_rdata),
        .m_axi_rresp(s_rresp),
        .m_axi_rlast(s_rlast),
        .m_axi_rvalid(s_rvalid),
        .m_axi_rready(s_rready)
    );

    ddr_axi_cdc u_cdc (
        .s_axi_aclk(clk_sys), .s_axi_aresetn(axi_sys_rst_n),
        .m_axi_aclk(ui_clk), .m_axi_aresetn(ui_rst_n),
        .s_axi_awregion(4'b0), .s_axi_arregion(4'b0),
        .m_axi_awregion(), .m_axi_arregion(),
        .s_axi_awid(s_awid),
        .s_axi_awaddr(s_awaddr),
        .s_axi_awlen(s_awlen),
        .s_axi_awsize(s_awsize),
        .s_axi_awburst(s_awburst),
        .s_axi_awlock(s_awlock),
        .s_axi_awcache(s_awcache),
        .s_axi_awprot(s_awprot),
        .s_axi_awqos(s_awqos),
        .s_axi_awvalid(s_awvalid),
        .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata),
        .s_axi_wstrb(s_wstrb),
        .s_axi_wlast(s_wlast),
        .s_axi_wvalid(s_wvalid),
        .s_axi_wready(s_wready),
        .s_axi_bid(s_bid),
        .s_axi_bresp(s_bresp),
        .s_axi_bvalid(s_bvalid),
        .s_axi_bready(s_bready),
        .s_axi_arid(s_arid),
        .s_axi_araddr(s_araddr),
        .s_axi_arlen(s_arlen),
        .s_axi_arsize(s_arsize),
        .s_axi_arburst(s_arburst),
        .s_axi_arlock(s_arlock),
        .s_axi_arcache(s_arcache),
        .s_axi_arprot(s_arprot),
        .s_axi_arqos(s_arqos),
        .s_axi_arvalid(s_arvalid),
        .s_axi_arready(s_arready),
        .s_axi_rid(s_rid),
        .s_axi_rdata(s_rdata),
        .s_axi_rresp(s_rresp),
        .s_axi_rlast(s_rlast),
        .s_axi_rvalid(s_rvalid),
        .s_axi_rready(s_rready),
        .m_axi_awid(m_awid),
        .m_axi_awaddr(m_awaddr),
        .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst),
        .m_axi_awlock(m_awlock),
        .m_axi_awcache(m_awcache),
        .m_axi_awprot(m_awprot),
        .m_axi_awqos(m_awqos),
        .m_axi_awvalid(m_awvalid),
        .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata),
        .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast),
        .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),
        .m_axi_bid(m_bid),
        .m_axi_bresp(m_bresp),
        .m_axi_bvalid(m_bvalid),
        .m_axi_bready(m_bready),
        .m_axi_arid(m_arid),
        .m_axi_araddr(m_araddr),
        .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize),
        .m_axi_arburst(m_arburst),
        .m_axi_arlock(m_arlock),
        .m_axi_arcache(m_arcache),
        .m_axi_arprot(m_arprot),
        .m_axi_arqos(m_arqos),
        .m_axi_arvalid(m_arvalid),
        .m_axi_arready(m_arready),
        .m_axi_rid(m_rid),
        .m_axi_rdata(m_rdata),
        .m_axi_rresp(m_rresp),
        .m_axi_rlast(m_rlast),
        .m_axi_rvalid(m_rvalid),
        .m_axi_rready(m_rready)
    );

    ddr3_mig u_mig (
        .ddr3_dq(ddr3_dq), .ddr3_dqs_n(ddr3_dqs_n), .ddr3_dqs_p(ddr3_dqs_p),
        .ddr3_addr(ddr3_addr), .ddr3_ba(ddr3_ba), .ddr3_ras_n(ddr3_ras_n),
        .ddr3_cas_n(ddr3_cas_n), .ddr3_we_n(ddr3_we_n), .ddr3_reset_n(ddr3_reset_n),
        .ddr3_ck_p(ddr3_ck_p), .ddr3_ck_n(ddr3_ck_n), .ddr3_cke(ddr3_cke),
        .ddr3_cs_n(ddr3_cs_n), .ddr3_dm(ddr3_dm), .ddr3_odt(ddr3_odt),
        .sys_clk_i(sys_clk_i), .clk_ref_i(clk_ref), .sys_rst(clock_reset_n),
        .ui_clk(ui_clk), .ui_clk_sync_rst(ui_reset), .mmcm_locked(),
        .init_calib_complete(calibrated), .aresetn(clock_reset_n),
        .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
        .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
        .device_temp_i(12'b0), .device_temp(),
        .s_axi_awid(m_awid),
        .s_axi_awaddr(m_awaddr),
        .s_axi_awlen(m_awlen),
        .s_axi_awsize(m_awsize),
        .s_axi_awburst(m_awburst),
        .s_axi_awlock(m_awlock),
        .s_axi_awcache(m_awcache),
        .s_axi_awprot(m_awprot),
        .s_axi_awqos(m_awqos),
        .s_axi_awvalid(m_awvalid),
        .s_axi_awready(m_awready),
        .s_axi_wdata(m_wdata),
        .s_axi_wstrb(m_wstrb),
        .s_axi_wlast(m_wlast),
        .s_axi_wvalid(m_wvalid),
        .s_axi_wready(m_wready),
        .s_axi_bid(m_bid),
        .s_axi_bresp(m_bresp),
        .s_axi_bvalid(m_bvalid),
        .s_axi_bready(m_bready),
        .s_axi_arid(m_arid),
        .s_axi_araddr(m_araddr),
        .s_axi_arlen(m_arlen),
        .s_axi_arsize(m_arsize),
        .s_axi_arburst(m_arburst),
        .s_axi_arlock(m_arlock),
        .s_axi_arcache(m_arcache),
        .s_axi_arprot(m_arprot),
        .s_axi_arqos(m_arqos),
        .s_axi_arvalid(m_arvalid),
        .s_axi_arready(m_arready),
        .s_axi_rid(m_rid),
        .s_axi_rdata(m_rdata),
        .s_axi_rresp(m_rresp),
        .s_axi_rlast(m_rlast),
        .s_axi_rvalid(m_rvalid),
        .s_axi_rready(m_rready)
    );
    assign led = {status[3:2], memory_ready, soc_rst_n};
endmodule

