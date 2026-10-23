// Portable Phase 8 SoC built around the variable-latency RV transaction bus.
`timescale 1ns/1ps

module soc_core #(
    parameter FIRMWARE_FILE = "firmware.vmem",
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer UART_BAUD = 115_200,
    parameter integer BRAM_SIZE_BYTES = 65_536,
    parameter bit FAST_LOCAL_IMEM = 1'b1,
    parameter bit FAST_LOCAL_DMEM = 1'b1,
    parameter bit ENABLE_EXT_MEM = 1'b0,
    parameter bit ENABLE_ICACHE = 1'b0,
    parameter bit ENABLE_DCACHE = 1'b0,
    parameter bit LOCAL_DCACHE = 1'b0,
    parameter bit BUFFER_WRITES = 1'b0,
    parameter bit STREAM_FETCH = 1'b0,
    parameter bit DUAL_ISSUE = 1'b0,
    parameter logic [31:0] EXT_MEM_BASE = 32'h8000_0000,
    parameter logic [31:0] EXT_MEM_BYTES = 32'h1000_0000
) (
    input  logic        clk_sys,
    input  logic        rst_n,
    output logic        uart_tx,
    input  logic        uart_rx,
    output logic        qspi_cs,
    output logic        qspi_sck,
    output logic        qspi_dq0_o,
    output logic        qspi_dq0_oe,
    input  logic        qspi_dq1_i,
    output logic [3:0]  status,
    // Optional external-memory target in clk_sys, shared by all four masters.
    input  logic        ext_mem_ready,
    output logic        ext_req_valid,
    input  logic        ext_req_ready,
    output logic [31:0] ext_req_addr,
    output logic        ext_req_write,
    output logic [3:0]  ext_req_wstrb,
    output logic [31:0] ext_req_wdata,
    output logic [1:0]  ext_req_size,
    input  logic        ext_rsp_valid,
    output logic        ext_rsp_ready,
    input  logic [31:0] ext_rsp_rdata,
    input  logic        ext_rsp_err
`ifdef SIMULATION
    ,input logic        sim_bus_override
    ,input logic [31:0] sim_bus_addr
    ,input logic [31:0] sim_bus_wdata
    ,input logic        sim_bus_rd_en
    ,input logic        sim_bus_wr_en
    ,input logic [2:0]  sim_bus_funct3
    ,input logic [3:0]  sim_irq_sources
`endif
);
    localparam logic [31:0] BRAM_BASE  = 32'h0000_0000;
    localparam logic [31:0] BRAM_MASK  = BRAM_SIZE_BYTES - 1;
    localparam logic [31:0] UART_BASE  = 32'h1000_0000;
    localparam logic [31:0] UART_MASK  = 32'h0000_000F;
    localparam logic [31:0] QSPI_BASE  = 32'h1000_1000;
    localparam logic [31:0] QSPI_MASK  = 32'h0000_000F;
    localparam logic [31:0] DMA_BASE   = 32'h1000_2000;
    localparam logic [31:0] DMA_MASK   = 32'h0000_001F;
    localparam logic [31:0] CLINT_BASE = 32'h0200_0000;
    localparam logic [31:0] CLINT_MASK = 32'h0000_FFFF;
    localparam logic [31:0] PLIC_BASE  = 32'h0C00_0000;
    localparam logic [31:0] PLIC_MASK  = 32'h003F_FFFF;
    localparam logic [31:0] MEMINFO_BASE = 32'h1000_3000;

    logic [31:0] dbg_pc, dbg_instr, dbg_alu_result, dbg_reg_rd_data;
    logic [31:0] cpu_imem_addr, cpu_imem_rdata;
    logic [31:0] cpu_dtcm_addr, cpu_dtcm_wdata, cpu_dtcm_rdata;
    logic [3:0]  cpu_dtcm_wstrb;
    logic        cpu_dtcm_rd_en, cpu_dtcm_wr_en, cpu_dtcm_access;

    // CPU data master.
    logic        cpu_d_req_valid, cpu_d_req_ready;
    logic [31:0] cpu_d_req_addr, cpu_d_req_wdata;
    logic        cpu_d_req_write;
    logic [3:0]  cpu_d_req_wstrb;
    logic [1:0]  cpu_d_req_size;
    logic        cpu_d_rsp_valid, cpu_d_rsp_ready, cpu_d_rsp_err;
    logic [31:0] cpu_d_rsp_rdata;

    // CPU instruction master.
    logic        cpu_i_req_valid, cpu_i_req_ready;
    logic [31:0] cpu_i_req_addr, cpu_i_req_wdata;
    logic        cpu_i_req_write;
    logic [3:0]  cpu_i_req_wstrb;
    logic [1:0]  cpu_i_req_size;
    logic        cpu_i_rsp_valid, cpu_i_rsp_ready, cpu_i_rsp_err;
    logic [31:0] cpu_i_rsp_rdata;

    // MMU page-table-walker master.
    logic        ptw_req_valid, ptw_req_ready;
    logic [31:0] ptw_req_addr, ptw_req_wdata;
    logic        ptw_req_write;
    logic [3:0]  ptw_req_wstrb;
    logic [1:0]  ptw_req_size;
    logic        ptw_rsp_valid, ptw_rsp_ready, ptw_rsp_err;
    logic [31:0] ptw_rsp_rdata;

    // DMA master.
    logic        dma_req_valid, dma_req_ready;
    logic [31:0] dma_req_addr, dma_req_wdata;
    logic        dma_req_write;
    logic [3:0]  dma_req_wstrb;
    logic [1:0]  dma_req_size;
    logic        dma_rsp_valid, dma_rsp_ready, dma_rsp_err;
    logic [31:0] dma_rsp_rdata;

    // Master 0 is normally CPU data. Simulation can temporarily replace it
    // with a host transaction without changing the synthesizable interface.
    logic        host_req_valid, host_req_ready;
    logic [31:0] host_req_addr, host_req_wdata;
    logic        host_req_write;
    logic [3:0]  host_req_wstrb;
    logic [1:0]  host_req_size;
    logic        host_rsp_valid, host_rsp_ready, host_rsp_err;
    logic [31:0] host_rsp_rdata;

`ifdef SIMULATION
    logic sim_master_active;
    // Test benches that do not use the host bus leave this optional input
    // unconnected. Treat X/Z as disabled so the CPU continues to own m0.
    logic sim_host_enable;
    logic sim_rsp_valid;
    logic sim_rsp_err;
    logic [31:0] sim_rsp_rdata;

    assign sim_host_enable = (sim_bus_override === 1'b1);
    assign host_req_valid = sim_host_enable ? (sim_bus_rd_en || sim_bus_wr_en) : cpu_d_req_valid;
    assign host_req_addr  = sim_host_enable ? sim_bus_addr : cpu_d_req_addr;
    assign host_req_write = sim_host_enable ? sim_bus_wr_en : cpu_d_req_write;
    assign host_req_wdata = sim_host_enable ? sim_bus_wdata : cpu_d_req_wdata;
    assign host_req_size  = sim_host_enable ?
                            ((sim_bus_funct3[1:0] == 2'b00) ? 2'd0 :
                             (sim_bus_funct3[1:0] == 2'b01) ? 2'd1 : 2'd2) : cpu_d_req_size;
    assign host_req_wstrb = sim_host_enable ?
                            (!sim_bus_wr_en ? 4'b0000 :
                             (host_req_size == 2'd0) ? 4'b0001 :
                             (host_req_size == 2'd1) ? 4'b0011 : 4'b1111) : cpu_d_req_wstrb;
    assign cpu_d_req_ready = !sim_host_enable && host_req_ready;
    assign cpu_d_rsp_valid = host_rsp_valid && !sim_master_active;
    assign cpu_d_rsp_rdata = host_rsp_rdata;
    assign cpu_d_rsp_err   = host_rsp_err;
    assign host_rsp_ready  = sim_master_active ? 1'b1 : cpu_d_rsp_ready;

    always_ff @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            sim_master_active <= 1'b0;
            sim_rsp_valid     <= 1'b0;
            sim_rsp_err       <= 1'b0;
            sim_rsp_rdata     <= 32'b0;
        end else begin
            sim_rsp_valid <= 1'b0;
            if (sim_host_enable && host_req_valid && host_req_ready)
                sim_master_active <= 1'b1;
            if (sim_master_active && host_rsp_valid && host_rsp_ready) begin
                sim_master_active <= 1'b0;
                sim_rsp_valid <= 1'b1;
                sim_rsp_err   <= host_rsp_err;
                sim_rsp_rdata <= host_rsp_rdata;
            end
        end
    end
`else
    assign host_req_valid = cpu_d_req_valid;
    assign host_req_addr  = cpu_d_req_addr;
    assign host_req_write = cpu_d_req_write;
    assign host_req_wstrb = cpu_d_req_wstrb;
    assign host_req_wdata = cpu_d_req_wdata;
    assign host_req_size  = cpu_d_req_size;
    assign cpu_d_req_ready = host_req_ready;
    assign cpu_d_rsp_valid = host_rsp_valid;
    assign cpu_d_rsp_rdata = host_rsp_rdata;
    assign cpu_d_rsp_err   = host_rsp_err;
    assign host_rsp_ready  = cpu_d_rsp_ready;
`endif

    // Shared slave transaction channel.
    logic        bus_req_valid, bus_req_ready;
    logic [31:0] bus_req_addr, bus_req_wdata;
    logic        bus_req_write;
    logic [3:0]  bus_req_wstrb;
    logic [1:0]  bus_req_size;
    logic        bus_rsp_valid, bus_rsp_ready, bus_rsp_err;
    logic [31:0] bus_rsp_rdata;

    logic ddr_req_valid, ddr_req_ready, ddr_rsp_valid, ddr_rsp_ready, ddr_rsp_err;
    logic [31:0] ddr_rsp_rdata;
    generate if (ENABLE_DCACHE && ENABLE_EXT_MEM && !LOCAL_DCACHE) begin : g_ddr_cache
        // Cache at the shared physical DDR port: CPU, DMA, instruction fills
        // and page-table reads observe the same ordered write-through data.
        rv_ddr_cache #(.BASE_ADDR(EXT_MEM_BASE), .SIZE_BYTES(EXT_MEM_BYTES)) u_cache (
            .clk(clk_sys), .rst_n(rst_n), .invalidate(!ext_mem_ready),
            .req_valid(ddr_req_valid), .req_ready(ddr_req_ready),
            .req_addr(bus_req_addr), .req_wdata(bus_req_wdata),
            .req_write(bus_req_write), .req_wstrb(bus_req_wstrb), .req_size(bus_req_size),
            .rsp_valid(ddr_rsp_valid), .rsp_ready(ddr_rsp_ready),
            .rsp_rdata(ddr_rsp_rdata), .rsp_err(ddr_rsp_err),
            .mem_req_valid(ext_req_valid), .mem_req_ready(ext_req_ready),
            .mem_req_addr(ext_req_addr), .mem_req_wdata(ext_req_wdata),
            .mem_req_write(ext_req_write), .mem_req_wstrb(ext_req_wstrb), .mem_req_size(ext_req_size),
            .mem_rsp_valid(ext_rsp_valid), .mem_rsp_ready(ext_rsp_ready),
            .mem_rsp_rdata(ext_rsp_rdata), .mem_rsp_err(ext_rsp_err)
        );
    end else begin : g_no_ddr_cache
        assign ext_req_valid = ddr_req_valid;
        assign ddr_req_ready = ext_req_ready;
        assign ext_req_addr = bus_req_addr;
        assign ext_req_write = bus_req_write;
        assign ext_req_wstrb = bus_req_wstrb;
        assign ext_req_wdata = bus_req_wdata;
        assign ext_req_size = bus_req_size;
        assign ddr_rsp_valid = ext_rsp_valid;
        assign ddr_rsp_rdata = ext_rsp_rdata;
        assign ddr_rsp_err = ext_rsp_err;
        assign ext_rsp_ready = ddr_rsp_ready;
    end endgenerate

    logic f_valid, f_ready, f_write, f_rsp_valid, f_rsp_ready, f_rsp_err;
    logic [31:0] f_addr, f_wdata, f_rdata;
    logic [3:0] f_strobes;
    logic [1:0] f_size;
    logic agent_active;
    // Exclusive DMA/PTW ownership: finish the current CPU access, drain
    // posted stores, flush local lines, then hold CPU requests until release.
    wire agent_pending = dma_req_valid || ptw_req_valid || agent_active;
    wire local_enabled = ENABLE_DCACHE && ENABLE_EXT_MEM && LOCAL_DCACHE;
    wire cache_idle, buffer_idle, buffer_fault;
    wire [31:0] buffer_fault_addr;
    wire agent_grant = !local_enabled || (cache_idle && buffer_idle && !buffer_fault);
    wire instruction_grant = !local_enabled || (buffer_idle && !buffer_fault);
    wire dma_f_ready, ptw_f_ready, instruction_f_ready;
    assign dma_req_ready = dma_f_ready && agent_grant;
    assign ptw_req_ready = ptw_f_ready && agent_grant;
    assign cpu_i_req_ready = instruction_f_ready && instruction_grant;
    always_ff @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) agent_active <= 0;
        else begin
            if ((dma_req_valid && dma_req_ready) || (ptw_req_valid && ptw_req_ready))
                agent_active <= 1;
            if ((dma_rsp_valid && dma_rsp_ready) || (ptw_rsp_valid && ptw_rsp_ready))
                agent_active <= 0;
        end
    end
    generate if (ENABLE_DCACHE && ENABLE_EXT_MEM && LOCAL_DCACHE) begin : g_local_cache
        wire cv, cr, cw, csv, csr, cse, front_ready, front_err;
        wire [31:0] ca, cd, csd;
        wire [3:0] cb;
        wire [1:0] cz;
        assign host_req_ready = front_ready && !agent_pending;
        // Posted errors cannot be reported precisely to the retired store.
        // Latch a fatal condition, discard cached data, and stop all bus work.
        assign host_rsp_err = front_err || buffer_fault;
        rv_ddr_cache #(.BASE_ADDR(EXT_MEM_BASE), .SIZE_BYTES(EXT_MEM_BYTES), .FAST_HIT(1)) u_cache (
            .clk(clk_sys), .rst_n(rst_n),
            .invalidate(agent_pending || !ext_mem_ready || buffer_fault), .idle(cache_idle),
            .req_valid(host_req_valid && !agent_pending), .req_ready(front_ready),
            .req_addr(host_req_addr), .req_wdata(host_req_wdata),
            .req_write(host_req_write), .req_wstrb(host_req_wstrb), .req_size(host_req_size),
            .rsp_valid(host_rsp_valid), .rsp_ready(host_rsp_ready),
            .rsp_rdata(host_rsp_rdata), .rsp_err(front_err),
            .mem_req_valid(cv), .mem_req_ready(cr), .mem_req_addr(ca), .mem_req_wdata(cd),
            .mem_req_write(cw), .mem_req_wstrb(cb), .mem_req_size(cz),
            .mem_rsp_valid(csv), .mem_rsp_ready(csr), .mem_rsp_rdata(csd), .mem_rsp_err(cse));
        rv_write_buffer #(.ENABLE(BUFFER_WRITES), .BASE_ADDR(EXT_MEM_BASE), .SIZE_BYTES(EXT_MEM_BYTES)) u_buffer (
            .clk(clk_sys), .rst_n(rst_n), .idle(buffer_idle), .fault(buffer_fault), .fault_addr(buffer_fault_addr),
            .req_valid(cv), .req_ready(cr), .req_addr(ca), .req_wdata(cd),
            .req_write(cw), .req_wstrb(cb), .req_size(cz),
            .rsp_valid(csv), .rsp_ready(csr), .rsp_rdata(csd), .rsp_err(cse),
            .mem_req_valid(f_valid), .mem_req_ready(f_ready), .mem_req_addr(f_addr), .mem_req_wdata(f_wdata),
            .mem_req_write(f_write), .mem_req_wstrb(f_strobes), .mem_req_size(f_size),
            .mem_rsp_valid(f_rsp_valid), .mem_rsp_ready(f_rsp_ready), .mem_rsp_rdata(f_rdata), .mem_rsp_err(f_rsp_err));
    end else begin : g_direct_data
        assign f_valid=host_req_valid; assign host_req_ready=f_ready;
        assign f_addr=host_req_addr; assign f_wdata=host_req_wdata;
        assign f_write=host_req_write; assign f_strobes=host_req_wstrb; assign f_size=host_req_size;
        assign host_rsp_valid=f_rsp_valid; assign f_rsp_ready=host_rsp_ready;
        assign host_rsp_rdata=f_rdata; assign host_rsp_err=f_rsp_err;
        assign cache_idle=1; assign buffer_idle=1; assign buffer_fault=0; assign buffer_fault_addr=0;
    end endgenerate

    rv_bus_arbiter u_bus_arbiter (
        .clk(clk_sys), .rst_n(rst_n),
        .m0_req_valid(f_valid), .m0_req_ready(f_ready),
        .m0_req_addr(f_addr), .m0_req_write(f_write),
        .m0_req_wstrb(f_strobes), .m0_req_wdata(f_wdata), .m0_req_size(f_size),
        .m0_rsp_valid(f_rsp_valid), .m0_rsp_ready(f_rsp_ready),
        .m0_rsp_rdata(f_rdata), .m0_rsp_err(f_rsp_err),
        .m1_req_valid(ptw_req_valid && agent_grant), .m1_req_ready(ptw_f_ready),
        .m1_req_addr(ptw_req_addr), .m1_req_write(ptw_req_write),
        .m1_req_wstrb(ptw_req_wstrb), .m1_req_wdata(ptw_req_wdata), .m1_req_size(ptw_req_size),
        .m1_rsp_valid(ptw_rsp_valid), .m1_rsp_ready(ptw_rsp_ready),
        .m1_rsp_rdata(ptw_rsp_rdata), .m1_rsp_err(ptw_rsp_err),
        .m2_req_valid(cpu_i_req_valid && instruction_grant), .m2_req_ready(instruction_f_ready),
        .m2_req_addr(cpu_i_req_addr), .m2_req_write(cpu_i_req_write),
        .m2_req_wstrb(cpu_i_req_wstrb), .m2_req_wdata(cpu_i_req_wdata), .m2_req_size(cpu_i_req_size),
        .m2_rsp_valid(cpu_i_rsp_valid), .m2_rsp_ready(cpu_i_rsp_ready),
        .m2_rsp_rdata(cpu_i_rsp_rdata), .m2_rsp_err(cpu_i_rsp_err),
        .m3_req_valid(dma_req_valid && agent_grant), .m3_req_ready(dma_f_ready),
        .m3_req_addr(dma_req_addr), .m3_req_write(dma_req_write),
        .m3_req_wstrb(dma_req_wstrb), .m3_req_wdata(dma_req_wdata), .m3_req_size(dma_req_size),
        .m3_rsp_valid(dma_rsp_valid), .m3_rsp_ready(dma_rsp_ready),
        .m3_rsp_rdata(dma_rsp_rdata), .m3_rsp_err(dma_rsp_err),
        .s_req_valid(bus_req_valid), .s_req_ready(bus_req_ready),
        .s_req_addr(bus_req_addr), .s_req_write(bus_req_write),
        .s_req_wstrb(bus_req_wstrb), .s_req_wdata(bus_req_wdata), .s_req_size(bus_req_size),
        .s_rsp_valid(bus_rsp_valid), .s_rsp_ready(bus_rsp_ready),
        .s_rsp_rdata(bus_rsp_rdata), .s_rsp_err(bus_rsp_err)
    );

    logic sel_bram, sel_uart, sel_qspi, sel_dma, sel_clint, sel_plic, sel_ext, sel_meminfo;
    logic target_mapped, target_endpoint_ready, target_accept;
    logic uart_tx_ready, uart_rx_valid;
    assign sel_bram  = ((bus_req_addr & ~BRAM_MASK) == BRAM_BASE);
    assign sel_uart  = ((bus_req_addr & ~UART_MASK) == UART_BASE);
    assign sel_qspi  = ((bus_req_addr & ~QSPI_MASK) == QSPI_BASE);
    assign sel_dma   = ((bus_req_addr & ~DMA_MASK) == DMA_BASE);
    assign sel_clint = ((bus_req_addr & ~CLINT_MASK) == CLINT_BASE);
    assign sel_plic  = ((bus_req_addr & ~PLIC_MASK) == PLIC_BASE);
    assign sel_ext = ENABLE_EXT_MEM && (bus_req_addr >= EXT_MEM_BASE) &&
                     ({1'b0, bus_req_addr} < {1'b0, EXT_MEM_BASE} + {1'b0, EXT_MEM_BYTES});
    assign sel_meminfo = ((bus_req_addr & 32'hFFFF_FFF0) == MEMINFO_BASE);
    assign target_mapped = sel_bram || sel_uart || sel_qspi || sel_dma || sel_clint || sel_plic ||
                           sel_ext || sel_meminfo;

    always_comb begin
        target_endpoint_ready = 1'b1;
        if (sel_ext && bus_req_size != 2'd3)
            target_endpoint_ready = ext_mem_ready && ddr_req_ready;
        else if (sel_bram && cpu_dtcm_access)
            target_endpoint_ready = 1'b0;
        else if (sel_uart && bus_req_write && bus_req_addr[3:0] == 4'h0)
            target_endpoint_ready = uart_tx_ready;
        else if (sel_uart && !bus_req_write && bus_req_addr[3:0] == 4'h4)
            target_endpoint_ready = uart_rx_valid;
    end

    typedef enum logic [1:0] {TARGET_IDLE, TARGET_WAIT, TARGET_RESPONSE, TARGET_EXTERNAL} target_state_t;
    target_state_t target_state;
    logic pending_bram_read;
    logic [31:0] target_read_hold;
    logic [31:0] target_rsp_data;
    logic target_rsp_error;

    assign bus_req_ready = (target_state == TARGET_IDLE) && target_endpoint_ready;
    assign target_accept = bus_req_valid && bus_req_ready;
    assign bus_rsp_valid = (target_state == TARGET_RESPONSE);
    assign bus_rsp_rdata = target_rsp_data;
    assign bus_rsp_err   = target_rsp_error;

    assign ddr_req_valid = ENABLE_EXT_MEM && ext_mem_ready && target_state == TARGET_IDLE &&
                           bus_req_valid && sel_ext && bus_req_size != 2'd3;
    assign ddr_rsp_ready = ENABLE_EXT_MEM && target_state == TARGET_EXTERNAL;

    logic [31:0] meminfo_rdata;
    always_comb begin
        case (bus_req_addr[3:0])
            4'h0: meminfo_rdata = 32'h4444_5231; // DDR1
            4'h4: meminfo_rdata = {25'b0, (ENABLE_ICACHE && STREAM_FETCH), buffer_fault, (local_enabled && BUFFER_WRITES), local_enabled,
                                  (ENABLE_EXT_MEM && ENABLE_DCACHE),
                                  (ENABLE_EXT_MEM && ext_mem_ready), ENABLE_EXT_MEM};
            4'h8: meminfo_rdata = EXT_MEM_BASE;
            4'hC: meminfo_rdata = ENABLE_EXT_MEM ? EXT_MEM_BYTES : 32'b0;
            default: meminfo_rdata = 32'b0;
        endcase
    end

    logic [31:0] bram_rdata, uart_rdata, qspi_rdata, dma_s_rdata, clint_rdata, plic_rdata;

    always_ff @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            target_state      <= TARGET_IDLE;
            pending_bram_read <= 1'b0;
            target_read_hold  <= 32'b0;
            target_rsp_data   <= 32'b0;
            target_rsp_error  <= 1'b0;
        end else begin
            case (target_state)
                TARGET_IDLE: begin
                    if (target_accept) begin
                        pending_bram_read <= sel_bram && !bus_req_write;
                        target_rsp_error  <= !target_mapped || (bus_req_size == 2'd3);
                        if (!bus_req_write) begin
                            if (sel_uart)       target_read_hold <= uart_rdata;
                            else if (sel_qspi) target_read_hold <= qspi_rdata;
                            else if (sel_dma)  target_read_hold <= dma_s_rdata;
                            else if (sel_clint)target_read_hold <= clint_rdata;
                            else if (sel_plic) target_read_hold <= plic_rdata;
                            else if (sel_meminfo) target_read_hold <= meminfo_rdata;
                            else               target_read_hold <= 32'b0;
                        end else begin
                            target_read_hold <= 32'b0;
                        end
                        target_state <= (sel_ext && bus_req_size != 2'd3) ? TARGET_EXTERNAL : TARGET_WAIT;
                    end
                end
                TARGET_WAIT: begin
                    target_rsp_data <= pending_bram_read ? bram_rdata : target_read_hold;
                    target_state    <= TARGET_RESPONSE;
                end
                TARGET_RESPONSE: begin
                    if (bus_rsp_ready)
                        target_state <= TARGET_IDLE;
                end
                TARGET_EXTERNAL: begin
                    if (ddr_rsp_valid) begin
                        target_rsp_data <= ddr_rsp_rdata;
                        target_rsp_error <= ddr_rsp_err;
                        target_state <= TARGET_RESPONSE;
                    end
                end
                default: target_state <= TARGET_IDLE;
            endcase
        end
    end

    assign cpu_dtcm_access = cpu_dtcm_rd_en || cpu_dtcm_wr_en;

    // Port A is the CPU instruction TCM. CPU local-data accesses get priority
    // on Port B; otherwise Port B serves the transaction fabric (DMA/PTW and
    // non-local CPU traffic). The target backpressures a simultaneous fabric
    // BRAM request, so the two paths can never drive the RAM together.
    bram #(.SIZE_BYTES(BRAM_SIZE_BYTES), .INIT_FILE(FIRMWARE_FILE)) u_bram (
        .clk(clk_sys), .a_addr(cpu_imem_addr), .a_rdata(cpu_imem_rdata),
        .b_addr(cpu_dtcm_access ? cpu_dtcm_addr : bus_req_addr),
        .b_wdata(cpu_dtcm_access ? cpu_dtcm_wdata : bus_req_wdata),
        .b_we(cpu_dtcm_wr_en ? cpu_dtcm_wstrb :
              ((target_accept && sel_bram && bus_req_write) ? bus_req_wstrb : 4'b0)),
        .b_re(cpu_dtcm_rd_en || (target_accept && sel_bram && !bus_req_write)),
        .b_rdata(bram_rdata)
    );
    assign cpu_dtcm_rdata = bram_rdata;

    logic uart_irq, timer_irq, software_irq, plic_irq, dma_irq;
    logic [4:0] plic_sources;
`ifdef SIMULATION
    assign plic_sources[0] = uart_irq | (sim_irq_sources[0] === 1'b1);
    assign plic_sources[1] = (sim_irq_sources[1] === 1'b1);
    assign plic_sources[2] = (sim_irq_sources[2] === 1'b1);
    assign plic_sources[3] = (sim_irq_sources[3] === 1'b1);
    assign plic_sources[4] = dma_irq;
`else
    assign plic_sources = {dma_irq, 3'b000, uart_irq};
`endif

    uart #(.CLK_FREQ(CLK_FREQ_HZ), .BAUD_RATE(UART_BAUD)) u_uart (
        .clk(clk_sys), .rst_n(rst_n), .addr(bus_req_addr[3:0]),
        .wr_data(bus_req_wdata),
        .wr_en(target_accept && sel_uart && bus_req_write),
        .rd_en(target_accept && sel_uart && !bus_req_write),
        .rd_data(uart_rdata), .irq(uart_irq),
        .tx_ready_o(uart_tx_ready), .rx_valid_o(uart_rx_valid),
        .uart_tx_pin(uart_tx), .uart_rx_pin(uart_rx)
    );

    dma_controller u_dma (
        .clk(clk_sys), .rst_n(rst_n), .s_addr(bus_req_addr[4:0]),
        .s_wr_data(bus_req_wdata),
        .s_wr_en(target_accept && sel_dma && bus_req_write),
        .s_rd_en(target_accept && sel_dma && !bus_req_write),
        .s_rd_data(dma_s_rdata),
        .m_req_valid(dma_req_valid), .m_req_ready(dma_req_ready),
        .m_req_addr(dma_req_addr), .m_req_write(dma_req_write),
        .m_req_wstrb(dma_req_wstrb), .m_req_wdata(dma_req_wdata), .m_req_size(dma_req_size),
        .m_rsp_valid(dma_rsp_valid), .m_rsp_ready(dma_rsp_ready),
        .m_rsp_rdata(dma_rsp_rdata), .m_rsp_err(dma_rsp_err), .irq(dma_irq)
    );

    qspi_reader u_qspi (
        .clk(clk_sys), .rst_n(rst_n), .addr(bus_req_addr[3:0]), .wr_data(bus_req_wdata),
        .wr_en(target_accept && sel_qspi && bus_req_write),
        .rd_en(target_accept && sel_qspi && !bus_req_write), .rd_data(qspi_rdata),
        .flash_cs_n(qspi_cs), .flash_sck(qspi_sck), .flash_dq0_o(qspi_dq0_o),
        .flash_dq0_oe(qspi_dq0_oe), .flash_dq1_i(qspi_dq1_i)
    );

    clint u_clint (
        .clk(clk_sys), .rst_n(rst_n), .addr(bus_req_addr[15:0]), .wr_data(bus_req_wdata),
        .wr_en(target_accept && sel_clint && bus_req_write),
        .rd_en(target_accept && sel_clint && !bus_req_write), .rd_data(clint_rdata),
        .software_irq(software_irq), .timer_irq(timer_irq)
    );

    plic #(.NUM_SOURCES(5)) u_plic (
        .clk(clk_sys), .rst_n(rst_n), .addr(bus_req_addr[21:0]), .wr_data(bus_req_wdata),
        .wr_en(target_accept && sel_plic && bus_req_write),
        .rd_en(target_accept && sel_plic && !bus_req_write),
        .source_irq(plic_sources), .rd_data(plic_rdata), .external_irq(plic_irq)
    );

    cpu_top_soc #(
        .XLEN(32),
        .ENABLE_MMU(1'b1),
        .ENABLE_ICACHE(ENABLE_ICACHE),
        .STREAM_FETCH(STREAM_FETCH),
        .DUAL_ISSUE(DUAL_ISSUE),
        .FAST_LOCAL_IMEM(FAST_LOCAL_IMEM),
        .FAST_LOCAL_DMEM(FAST_LOCAL_DMEM),
        .LOCAL_MEM_BYTES(BRAM_SIZE_BYTES)
    ) u_cpu (
        .clk(clk_sys), .rst_n(rst_n), .ext_interrupt(plic_irq),
        .timer_interrupt(timer_irq), .software_interrupt(software_irq),
        .imem_addr(cpu_imem_addr), .imem_rdata(cpu_imem_rdata),
        .dtcm_addr(cpu_dtcm_addr), .dtcm_wdata(cpu_dtcm_wdata),
        .dtcm_wstrb(cpu_dtcm_wstrb), .dtcm_rd_en(cpu_dtcm_rd_en),
        .dtcm_wr_en(cpu_dtcm_wr_en), .dtcm_rdata(cpu_dtcm_rdata),
        .ibus_req_valid(cpu_i_req_valid), .ibus_req_ready(cpu_i_req_ready),
        .ibus_req_addr(cpu_i_req_addr), .ibus_req_write(cpu_i_req_write),
        .ibus_req_wstrb(cpu_i_req_wstrb), .ibus_req_wdata(cpu_i_req_wdata), .ibus_req_size(cpu_i_req_size),
        .ibus_rsp_valid(cpu_i_rsp_valid), .ibus_rsp_ready(cpu_i_rsp_ready),
        .ibus_rsp_rdata(cpu_i_rsp_rdata), .ibus_rsp_err(cpu_i_rsp_err),
        .dbus_req_valid(cpu_d_req_valid), .dbus_req_ready(cpu_d_req_ready),
        .dbus_req_addr(cpu_d_req_addr), .dbus_req_write(cpu_d_req_write),
        .dbus_req_wstrb(cpu_d_req_wstrb), .dbus_req_wdata(cpu_d_req_wdata), .dbus_req_size(cpu_d_req_size),
        .dbus_rsp_valid(cpu_d_rsp_valid), .dbus_rsp_ready(cpu_d_rsp_ready),
        .dbus_rsp_rdata(cpu_d_rsp_rdata), .dbus_rsp_err(cpu_d_rsp_err),
        .ptw_req_valid(ptw_req_valid), .ptw_req_ready(ptw_req_ready),
        .ptw_req_addr(ptw_req_addr), .ptw_req_write(ptw_req_write),
        .ptw_req_wstrb(ptw_req_wstrb), .ptw_req_wdata(ptw_req_wdata), .ptw_req_size(ptw_req_size),
        .ptw_rsp_valid(ptw_rsp_valid), .ptw_rsp_ready(ptw_rsp_ready),
        .ptw_rsp_rdata(ptw_rsp_rdata), .ptw_rsp_err(ptw_rsp_err),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr), .dbg_alu_result(dbg_alu_result),
        .dbg_reg_rd_data(dbg_reg_rd_data)
    );

    assign status[0] = rst_n;
    assign status[1] = !buffer_fault;
    assign status[2] = ~uart_tx;
    assign status[3] = ~uart_rx;
endmodule
