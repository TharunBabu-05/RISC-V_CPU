// Four-master, single-outstanding transaction-bus arbiter.
//
// A request is accepted when req_valid && req_ready. The selected owner is
// then locked until its response is accepted. Responses may take any number
// of cycles, which makes this fabric suitable for BRAM, peripherals, cache
// refills, DDR controllers and AXI bridges.
`timescale 1ns/1ps

module rv_bus_arbiter (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        m0_req_valid,
    output logic        m0_req_ready,
    input  logic [31:0] m0_req_addr,
    input  logic        m0_req_write,
    input  logic [3:0]  m0_req_wstrb,
    input  logic [31:0] m0_req_wdata,
    input  logic [1:0]  m0_req_size,
    output logic        m0_rsp_valid,
    input  logic        m0_rsp_ready,
    output logic [31:0] m0_rsp_rdata,
    output logic        m0_rsp_err,

    input  logic        m1_req_valid,
    output logic        m1_req_ready,
    input  logic [31:0] m1_req_addr,
    input  logic        m1_req_write,
    input  logic [3:0]  m1_req_wstrb,
    input  logic [31:0] m1_req_wdata,
    input  logic [1:0]  m1_req_size,
    output logic        m1_rsp_valid,
    input  logic        m1_rsp_ready,
    output logic [31:0] m1_rsp_rdata,
    output logic        m1_rsp_err,

    input  logic        m2_req_valid,
    output logic        m2_req_ready,
    input  logic [31:0] m2_req_addr,
    input  logic        m2_req_write,
    input  logic [3:0]  m2_req_wstrb,
    input  logic [31:0] m2_req_wdata,
    input  logic [1:0]  m2_req_size,
    output logic        m2_rsp_valid,
    input  logic        m2_rsp_ready,
    output logic [31:0] m2_rsp_rdata,
    output logic        m2_rsp_err,

    input  logic        m3_req_valid,
    output logic        m3_req_ready,
    input  logic [31:0] m3_req_addr,
    input  logic        m3_req_write,
    input  logic [3:0]  m3_req_wstrb,
    input  logic [31:0] m3_req_wdata,
    input  logic [1:0]  m3_req_size,
    output logic        m3_rsp_valid,
    input  logic        m3_rsp_ready,
    output logic [31:0] m3_rsp_rdata,
    output logic        m3_rsp_err,

    output logic        s_req_valid,
    input  logic        s_req_ready,
    output logic [31:0] s_req_addr,
    output logic        s_req_write,
    output logic [3:0]  s_req_wstrb,
    output logic [31:0] s_req_wdata,
    output logic [1:0]  s_req_size,
    input  logic        s_rsp_valid,
    output logic        s_rsp_ready,
    input  logic [31:0] s_rsp_rdata,
    input  logic        s_rsp_err
);
    logic       busy;
    logic [1:0] owner;
    logic [1:0] last_owner;
    logic [1:0] selected;
    logic       selected_valid;
    integer     offset;
    integer     candidate;

    // Round-robin selection prevents a continuous instruction stream from
    // starving DMA or a page-table walk.
    always_comb begin
        selected       = 2'd0;
        selected_valid = 1'b0;
        for (offset = 1; offset <= 4; offset = offset + 1) begin
            candidate = (last_owner + offset) & 3;
            if (!selected_valid) begin
                case (candidate)
                    0: if (m0_req_valid) begin selected = 2'd0; selected_valid = 1'b1; end
                    1: if (m1_req_valid) begin selected = 2'd1; selected_valid = 1'b1; end
                    2: if (m2_req_valid) begin selected = 2'd2; selected_valid = 1'b1; end
                    3: if (m3_req_valid) begin selected = 2'd3; selected_valid = 1'b1; end
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        m0_req_ready = 1'b0;
        m1_req_ready = 1'b0;
        m2_req_ready = 1'b0;
        m3_req_ready = 1'b0;
        m0_rsp_valid = 1'b0;
        m1_rsp_valid = 1'b0;
        m2_rsp_valid = 1'b0;
        m3_rsp_valid = 1'b0;
        m0_rsp_rdata = s_rsp_rdata;
        m1_rsp_rdata = s_rsp_rdata;
        m2_rsp_rdata = s_rsp_rdata;
        m3_rsp_rdata = s_rsp_rdata;
        m0_rsp_err   = s_rsp_err;
        m1_rsp_err   = s_rsp_err;
        m2_rsp_err   = s_rsp_err;
        m3_rsp_err   = s_rsp_err;

        s_req_valid = 1'b0;
        s_req_addr  = 32'b0;
        s_req_write = 1'b0;
        s_req_wstrb = 4'b0;
        s_req_wdata = 32'b0;
        s_req_size  = 2'b0;
        s_rsp_ready = 1'b0;

        if (!busy && selected_valid) begin
            s_req_valid = 1'b1;
            case (selected)
                2'd0: begin
                    s_req_addr = m0_req_addr; s_req_write = m0_req_write;
                    s_req_wstrb = m0_req_wstrb; s_req_wdata = m0_req_wdata;
                    s_req_size = m0_req_size; m0_req_ready = s_req_ready;
                end
                2'd1: begin
                    s_req_addr = m1_req_addr; s_req_write = m1_req_write;
                    s_req_wstrb = m1_req_wstrb; s_req_wdata = m1_req_wdata;
                    s_req_size = m1_req_size; m1_req_ready = s_req_ready;
                end
                2'd2: begin
                    s_req_addr = m2_req_addr; s_req_write = m2_req_write;
                    s_req_wstrb = m2_req_wstrb; s_req_wdata = m2_req_wdata;
                    s_req_size = m2_req_size; m2_req_ready = s_req_ready;
                end
                default: begin
                    s_req_addr = m3_req_addr; s_req_write = m3_req_write;
                    s_req_wstrb = m3_req_wstrb; s_req_wdata = m3_req_wdata;
                    s_req_size = m3_req_size; m3_req_ready = s_req_ready;
                end
            endcase
        end else if (busy) begin
            case (owner)
                2'd0: begin m0_rsp_valid = s_rsp_valid; s_rsp_ready = m0_rsp_ready; end
                2'd1: begin m1_rsp_valid = s_rsp_valid; s_rsp_ready = m1_rsp_ready; end
                2'd2: begin m2_rsp_valid = s_rsp_valid; s_rsp_ready = m2_rsp_ready; end
                default: begin m3_rsp_valid = s_rsp_valid; s_rsp_ready = m3_rsp_ready; end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy       <= 1'b0;
            owner      <= 2'd0;
            last_owner <= 2'd3;
        end else begin
            if (!busy && s_req_valid && s_req_ready) begin
                busy  <= 1'b1;
                owner <= selected;
            end else if (busy && s_rsp_valid && s_rsp_ready) begin
                busy       <= 1'b0;
                last_owner <= owner;
            end
        end
    end
endmodule
