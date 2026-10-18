`timescale 1ns/1ps

module tb_dma_controller;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic [4:0] s_addr;
    logic [31:0] s_wr_data;
    logic s_wr_en;
    logic s_rd_en;
    logic [31:0] s_rd_data;
    logic m_req_valid, m_req_ready, m_req_write;
    logic [31:0] m_req_addr, m_req_wdata;
    logic [3:0] m_req_wstrb;
    logic [1:0] m_req_size;
    logic m_rsp_valid, m_rsp_ready, m_rsp_err;
    logic [31:0] m_rsp_rdata;
    logic irq;
    logic allow_ready = 1'b1;
    logic pending;
    logic [2:0] response_delay;
    logic response_error;
    logic [31:0] response_data;
    logic [7:0] memory [0:255];
    logic [31:0] value;
    integer errors = 0;
    integer i;

    dma_controller dut (.*);

    assign m_req_ready = allow_ready && !pending && !m_rsp_valid;

    // Delayed target: both reads and writes receive an explicit response.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending        <= 1'b0;
            response_delay <= 3'd0;
            response_error <= 1'b0;
            response_data  <= 32'b0;
            m_rsp_valid    <= 1'b0;
            m_rsp_rdata    <= 32'b0;
            m_rsp_err      <= 1'b0;
        end else begin
            if (m_rsp_valid && m_rsp_ready)
                m_rsp_valid <= 1'b0;

            if (m_req_valid && m_req_ready) begin
                pending        <= 1'b1;
                response_delay <= 3'd3;
                response_error <= (m_req_addr > 32'h0000_00FF);
                response_data  <= {memory[m_req_addr + 3], memory[m_req_addr + 2],
                                   memory[m_req_addr + 1], memory[m_req_addr]};
                if (m_req_write && (m_req_addr <= 32'h0000_00FF)) begin
                    if (m_req_wstrb[0]) memory[m_req_addr]     <= m_req_wdata[7:0];
                    if (m_req_wstrb[1]) memory[m_req_addr + 1] <= m_req_wdata[15:8];
                    if (m_req_wstrb[2]) memory[m_req_addr + 2] <= m_req_wdata[23:16];
                    if (m_req_wstrb[3]) memory[m_req_addr + 3] <= m_req_wdata[31:24];
                end
            end

            if (pending) begin
                if (response_delay != 0)
                    response_delay <= response_delay - 1'b1;
                else begin
                    pending     <= 1'b0;
                    m_rsp_valid <= 1'b1;
                    m_rsp_err   <= response_error;
                    m_rsp_rdata <= response_data;
                end
            end
        end
    end

    task automatic reg_write(input [4:0] address, input [31:0] data);
        begin
            @(negedge clk);
            s_addr = address;
            s_wr_data = data;
            s_wr_en = 1'b1;
            s_rd_en = 1'b0;
            @(negedge clk);
            s_wr_en = 1'b0;
        end
    endtask

    task automatic reg_read(input [4:0] address, output [31:0] data);
        begin
            @(negedge clk);
            s_addr = address;
            s_rd_en = 1'b1;
            s_wr_en = 1'b0;
            #1 data = s_rd_data;
            @(negedge clk);
            s_rd_en = 1'b0;
        end
    endtask

    task automatic wait_idle;
        integer timeout;
        begin
            timeout = 0;
            while (dut.busy && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 1000) begin
                errors = errors + 1;
                $error("DMA timeout");
            end
        end
    endtask

    task automatic check(input string what, input logic condition);
        begin
            if (!condition) begin
                errors = errors + 1;
                $error("FAIL %s", what);
            end else begin
                $display("PASS %s", what);
            end
        end
    endtask

    initial begin
        s_addr = 0;
        s_wr_data = 0;
        s_wr_en = 0;
        s_rd_en = 0;
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        reg_read(5'h18, value);
        check("DMA peripheral ID", value == 32'h444D_4131);

        // Word transfers with a final one-byte tail.
        for (i = 0; i < 13; i = i + 1)
            memory[8'h10 + i] = 8'h80 + i;
        reg_write(5'h00, 32'h10);
        reg_write(5'h04, 32'h80);
        reg_write(5'h08, 32'd13);
        reg_write(5'h0C, 32'h0000_0037); // start, inc/inc, word, IRQ
        wait_idle();
        for (i = 0; i < 13; i = i + 1)
            check("word copy byte", memory[8'h80 + i] == (8'h80 + i));
        reg_read(5'h10, value);
        check("completion and IRQ status", value[3:0] == 4'b1010);
        check("completion IRQ output", irq);
        reg_read(5'h14, value);
        check("transferred byte count", value == 13);
        reg_read(5'h1C, value);
        check("remaining byte count", value == 0);

        // A fixed destination models a TX FIFO data register.
        memory[8'h20] = 8'h11;
        memory[8'h21] = 8'h22;
        memory[8'h22] = 8'h33;
        reg_write(5'h00, 32'h20);
        reg_write(5'h04, 32'hE0);
        reg_write(5'h08, 32'd3);
        reg_write(5'h0C, 32'h0000_0003); // start + source increment
        wait_idle();
        check("fixed destination receives final byte", memory[8'hE0] == 8'h33);

        // Request-ready backpressure must hold a request without losing progress.
        allow_ready = 1'b0;
        reg_write(5'h00, 32'h10);
        reg_write(5'h04, 32'hA0);
        reg_write(5'h08, 32'd4);
        reg_write(5'h0C, 32'h0000_0017);
        repeat (8) @(posedge clk);
        check("ready backpressure keeps DMA busy", dut.busy && (dut.transferred == 0));
        allow_ready = 1'b1;
        wait_idle();
        check("transfer resumes after backpressure", memory[8'hA0] == memory[8'h10]);

        // Software can terminate a blocked transfer without resetting DMA.
        allow_ready = 1'b0;
        reg_write(5'h00, 32'h10);
        reg_write(5'h04, 32'hB0);
        reg_write(5'h08, 32'd4);
        reg_write(5'h0C, 32'h0000_0027);
        repeat (3) @(posedge clk);
        reg_write(5'h0C, 32'h0000_0040);
        reg_read(5'h10, value);
        check("active transfer can be aborted",
              !value[0] && value[2] && value[3] && value[15:8] == 8'h04);
        allow_ready = 1'b1;

        // Unmapped bus access fails and can interrupt the PLIC.
        reg_write(5'h00, 32'h0000_1000);
        reg_write(5'h04, 32'h0000_0040);
        reg_write(5'h08, 32'd1);
        reg_write(5'h0C, 32'h0000_0021);
        wait_idle();
        reg_read(5'h10, value);
        check("bus error is reported", value[2] && value[3] && value[15:8] == 8'h03);

        // The DMA register window is explicitly protected from self-access.
        reg_write(5'h00, 32'h1000_2000);
        reg_write(5'h04, 32'h0000_0040);
        reg_write(5'h08, 32'd1);
        reg_write(5'h0C, 32'h0000_0001);
        reg_read(5'h10, value);
        check("self-access is rejected", value[2] && value[15:8] == 8'h02);

        // Invalid transfer width must fail immediately.
        reg_write(5'h00, 32'h10);
        reg_write(5'h04, 32'h40);
        reg_write(5'h08, 32'd1);
        reg_write(5'h0C, 32'h0000_0019);
        reg_read(5'h10, value);
        check("reserved width is rejected", value[2] && value[15:8] == 8'h01);

        if (errors == 0)
            $display("PASS: DMA controller tests");
        else
            $fatal(1, "DMA controller tests failed: %0d", errors);
        $finish;
    end
endmodule
