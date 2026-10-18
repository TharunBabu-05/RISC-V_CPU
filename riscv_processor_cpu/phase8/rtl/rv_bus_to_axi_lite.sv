// RV transaction bus to 32-bit AXI4-Lite master bridge.
//
// The RV bus uses exact byte addresses and right-justified read/write data.
// This bridge aligns AXI addresses and splits accesses that cross a 32-bit
// boundary. It keeps one RV transaction outstanding and handles independent
// AXI address/data backpressure.
`timescale 1ns/1ps

module rv_bus_to_axi_lite (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        bus_req_valid,
    output logic        bus_req_ready,
    input  logic [31:0] bus_req_addr,
    input  logic        bus_req_write,
    input  logic [3:0]  bus_req_wstrb,
    input  logic [31:0] bus_req_wdata,
    input  logic [1:0]  bus_req_size,
    output logic        bus_rsp_valid,
    input  logic        bus_rsp_ready,
    output logic [31:0] bus_rsp_rdata,
    output logic        bus_rsp_err,

    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);
    typedef enum logic [2:0] {
        ST_IDLE, ST_W_SEND, ST_W_RESP, ST_R_ADDR, ST_R_DATA, ST_RESPONSE
    } state_t;

    state_t state;
    logic [31:0] req_addr;
    logic [31:0] req_wdata;
    logic [3:0]  req_wstrb;
    logic [1:0]  req_size;
    logic        second_beat;
    logic        beat_index;
    logic        aw_done;
    logic        w_done;
    logic [31:0] first_rdata;
    logic        error_seen;
    logic [2:0]  byte_count;
    logic [2:0]  first_bytes;
    logic [4:0]  shift_bits;

    always_comb begin
        case (req_size)
            2'd0: byte_count = 3'd1;
            2'd1: byte_count = 3'd2;
            default: byte_count = 3'd4;
        endcase
        first_bytes = 3'd4 - {1'b0, req_addr[1:0]};
        shift_bits  = first_bytes * 8;
    end

    assign bus_req_ready = (state == ST_IDLE);
    assign bus_rsp_valid = (state == ST_RESPONSE);

    always_comb begin
        m_axi_awaddr  = {req_addr[31:2], 2'b00} + (beat_index ? 32'd4 : 32'd0);
        m_axi_awvalid = (state == ST_W_SEND) && !aw_done;
        m_axi_wvalid  = (state == ST_W_SEND) && !w_done;
        m_axi_bready  = (state == ST_W_RESP);
        m_axi_araddr  = {req_addr[31:2], 2'b00} + (beat_index ? 32'd4 : 32'd0);
        m_axi_arvalid = (state == ST_R_ADDR);
        m_axi_rready  = (state == ST_R_DATA);

        if (!beat_index) begin
            m_axi_wdata = req_wdata << (req_addr[1:0] * 8);
            m_axi_wstrb = req_wstrb << req_addr[1:0];
        end else begin
            m_axi_wdata = req_wdata >> shift_bits;
            m_axi_wstrb = req_wstrb >> first_bytes;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            req_addr       <= 32'b0;
            req_wdata      <= 32'b0;
            req_wstrb      <= 4'b0;
            req_size       <= 2'b0;
            second_beat    <= 1'b0;
            beat_index     <= 1'b0;
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            first_rdata    <= 32'b0;
            bus_rsp_rdata  <= 32'b0;
            bus_rsp_err    <= 1'b0;
            error_seen     <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (bus_req_valid && bus_req_ready) begin
                        req_addr    <= bus_req_addr;
                        req_wdata   <= bus_req_wdata;
                        req_wstrb   <= bus_req_wstrb;
                        req_size    <= bus_req_size;
                        second_beat <= ({1'b0, bus_req_addr[1:0]} +
                                        ((bus_req_size == 2'd0) ? 3'd1 :
                                         (bus_req_size == 2'd1) ? 3'd2 : 3'd4)) > 3'd4;
                        beat_index  <= 1'b0;
                        aw_done     <= 1'b0;
                        w_done      <= 1'b0;
                        error_seen  <= 1'b0;
                        bus_rsp_err <= 1'b0;
                        state       <= bus_req_write ? ST_W_SEND : ST_R_ADDR;
                    end
                end

                ST_W_SEND: begin
                    if (m_axi_awvalid && m_axi_awready)
                        aw_done <= 1'b1;
                    if (m_axi_wvalid && m_axi_wready)
                        w_done <= 1'b1;
                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done || (m_axi_wvalid && m_axi_wready)))
                        state <= ST_W_RESP;
                end

                ST_W_RESP: begin
                    if (m_axi_bvalid) begin
                        error_seen <= error_seen || m_axi_bresp[1];
                        if (!beat_index && second_beat && !m_axi_bresp[1]) begin
                            beat_index <= 1'b1;
                            aw_done    <= 1'b0;
                            w_done     <= 1'b0;
                            state      <= ST_W_SEND;
                        end else begin
                            bus_rsp_rdata <= 32'b0;
                            bus_rsp_err   <= error_seen || m_axi_bresp[1];
                            state         <= ST_RESPONSE;
                        end
                    end
                end

                ST_R_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready)
                        state <= ST_R_DATA;
                end

                ST_R_DATA: begin
                    if (m_axi_rvalid) begin
                        error_seen <= error_seen || m_axi_rresp[1];
                        if (!beat_index) begin
                            first_rdata <= m_axi_rdata;
                            if (second_beat && !m_axi_rresp[1]) begin
                                beat_index <= 1'b1;
                                state      <= ST_R_ADDR;
                            end else begin
                                bus_rsp_rdata <= m_axi_rdata >> (req_addr[1:0] * 8);
                                bus_rsp_err   <= error_seen || m_axi_rresp[1];
                                state         <= ST_RESPONSE;
                            end
                        end else begin
                            bus_rsp_rdata <= (first_rdata >> (req_addr[1:0] * 8)) |
                                             (m_axi_rdata << shift_bits);
                            bus_rsp_err   <= error_seen || m_axi_rresp[1];
                            state         <= ST_RESPONSE;
                        end
                    end
                end

                ST_RESPONSE: begin
                    if (bus_rsp_ready)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
