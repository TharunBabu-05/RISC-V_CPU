// Blocking RV bus to the Arty MIG's 128-bit AXI4 port.
// Each AXI transfer is one aligned, full-width beat (no narrow bursts).
// Exact byte addresses/right-justified RV data are preserved, including
// accesses crossing a 16-byte boundary. AW and W may stall independently.
`timescale 1ns/1ps

module rv_bus_to_axi128 #(
    parameter logic [31:0] BASE_ADDR = 32'h8000_0000,
    parameter logic [31:0] SIZE_BYTES = 32'h1000_0000
) (
    input logic clk, rst_n, memory_ready,
    input logic bus_req_valid,
    output logic bus_req_ready,
    input logic [31:0] bus_req_addr, bus_req_wdata,
    input logic bus_req_write,
    input logic [3:0] bus_req_wstrb,
    input logic [1:0] bus_req_size,
    output logic bus_rsp_valid,
    input logic bus_rsp_ready,
    output logic [31:0] bus_rsp_rdata,
    output logic bus_rsp_err,

    output logic [3:0] m_axi_awid,
    output logic [27:0] m_axi_awaddr,
    output logic [7:0] m_axi_awlen,
    output logic [2:0] m_axi_awsize,
    output logic [1:0] m_axi_awburst,
    output logic m_axi_awlock,
    output logic [3:0] m_axi_awcache,
    output logic [2:0] m_axi_awprot,
    output logic [3:0] m_axi_awqos,
    output logic m_axi_awvalid,
    input logic m_axi_awready,
    output logic [127:0] m_axi_wdata,
    output logic [15:0] m_axi_wstrb,
    output logic m_axi_wlast, m_axi_wvalid,
    input logic m_axi_wready,
    input logic [3:0] m_axi_bid,
    input logic [1:0] m_axi_bresp,
    input logic m_axi_bvalid,
    output logic m_axi_bready,
    output logic [3:0] m_axi_arid,
    output logic [27:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen,
    output logic [2:0] m_axi_arsize,
    output logic [1:0] m_axi_arburst,
    output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache,
    output logic [2:0] m_axi_arprot,
    output logic [3:0] m_axi_arqos,
    output logic m_axi_arvalid,
    input logic m_axi_arready,
    input logic [3:0] m_axi_rid,
    input logic [127:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp,
    input logic m_axi_rlast, m_axi_rvalid,
    output logic m_axi_rready
);
    typedef enum logic [2:0] {IDLE, WRITE_SEND, WRITE_RESP, READ_ADDR,
                              READ_DATA, RESPONSE} state_t;
    state_t state;
    logic [27:0] offset;
    logic [31:0] write_data, first_read;
    logic [3:0] write_strobes;
    logic [2:0] count;
    logic second_needed, second, aw_sent, w_sent, read_error;
    logic [4:0] first_bytes;
    logic [2:0] request_bytes;
    logic [31:0] read_mask;
    logic invalid_request;

    assign request_bytes = (bus_req_size == 0) ? 3'd1 :
                            (bus_req_size == 1) ? 3'd2 : 3'd4;
    assign invalid_request = !memory_ready || bus_req_size == 3 ||
        bus_req_addr < BASE_ADDR ||
        ({1'b0, bus_req_addr} + request_bytes > {1'b0, BASE_ADDR} + {1'b0, SIZE_BYTES}) ||
        (bus_req_write && (({1'b0, bus_req_wstrb} >> request_bytes) != 0));
    assign first_bytes = 5'd16 - {1'b0, offset[3:0]};
    assign read_mask = (count == 1) ? 32'hFF : (count == 2) ? 32'hFFFF : 32'hFFFF_FFFF;
    assign bus_req_ready = rst_n && state == IDLE;
    assign bus_rsp_valid = state == RESPONSE;

    assign m_axi_awid = 0;
    assign m_axi_awaddr = {offset[27:4], 4'b0} + (second ? 28'd16 : 28'd0);
    assign m_axi_awlen = 0;
    assign m_axi_awsize = 3'd4;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock = 0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot = 0;
    assign m_axi_awqos = 0;
    assign m_axi_awvalid = state == WRITE_SEND && !aw_sent;
    assign m_axi_wdata = second ? ({96'b0, write_data} >> (first_bytes * 8)) :
                                  ({96'b0, write_data} << (offset[3:0] * 8));
    assign m_axi_wstrb = second ? ({12'b0, write_strobes} >> first_bytes) :
                                  ({12'b0, write_strobes} << offset[3:0]);
    assign m_axi_wlast = 1'b1;
    assign m_axi_wvalid = state == WRITE_SEND && !w_sent;
    assign m_axi_bready = state == WRITE_RESP;
    assign m_axi_arid = 0;
    assign m_axi_araddr = m_axi_awaddr;
    assign m_axi_arlen = 0;
    assign m_axi_arsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot = 0;
    assign m_axi_arqos = 0;
    assign m_axi_arvalid = state == READ_ADDR;
    assign m_axi_rready = state == READ_DATA;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            offset <= 0;
            write_data <= 0;
            write_strobes <= 0;
            first_read <= 0;
            count <= 0;
            second_needed <= 0;
            second <= 0;
            aw_sent <= 0;
            w_sent <= 0;
            read_error <= 0;
            bus_rsp_rdata <= 0;
            bus_rsp_err <= 0;
        end else begin
            case (state)
                IDLE: if (bus_req_valid) begin
                    offset <= bus_req_addr - BASE_ADDR;
                    write_data <= bus_req_wdata;
                    write_strobes <= bus_req_wstrb;
                    count <= request_bytes;
                    second_needed <= ({1'b0, bus_req_addr[3:0]} + request_bytes > 16);
                    second <= 0;
                    aw_sent <= 0;
                    w_sent <= 0;
                    read_error <= 0;
                    bus_rsp_rdata <= 0;
                    bus_rsp_err <= invalid_request;
                    state <= invalid_request ? RESPONSE :
                             bus_req_write ? WRITE_SEND : READ_ADDR;
                end
                WRITE_SEND: begin
                    if (m_axi_awvalid && m_axi_awready) aw_sent <= 1;
                    if (m_axi_wvalid && m_axi_wready) w_sent <= 1;
                    if ((aw_sent || m_axi_awready) && (w_sent || m_axi_wready))
                        state <= WRITE_RESP;
                end
                WRITE_RESP: if (m_axi_bvalid) begin
                    if (m_axi_bresp[1] || m_axi_bid != 0) begin
                        bus_rsp_err <= 1;
                        state <= RESPONSE;
                    end else if (!second && second_needed) begin
                        second <= 1;
                        aw_sent <= 0;
                        w_sent <= 0;
                        state <= WRITE_SEND;
                    end else state <= RESPONSE;
                end
                READ_ADDR: if (m_axi_arready) state <= READ_DATA;
                READ_DATA: if (m_axi_rvalid) begin
                    // Drain through RLAST even on a malformed multi-beat reply.
                    if (!m_axi_rlast || m_axi_rresp[1] || m_axi_rid != 0)
                        read_error <= 1;
                    if (m_axi_rlast) begin
                        if (read_error || m_axi_rresp[1] || m_axi_rid != 0) begin
                            bus_rsp_err <= 1;
                            bus_rsp_rdata <= 0;
                            state <= RESPONSE;
                        end else if (!second && second_needed) begin
                            first_read <= m_axi_rdata >> (offset[3:0] * 8);
                            second <= 1;
                            state <= READ_ADDR;
                        end else begin
                            bus_rsp_rdata <= (second ?
                                (first_read | (m_axi_rdata << (first_bytes * 8))) :
                                (m_axi_rdata >> (offset[3:0] * 8))) & read_mask;
                            state <= RESPONSE;
                        end
                    end
                end
                RESPONSE: if (bus_rsp_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
