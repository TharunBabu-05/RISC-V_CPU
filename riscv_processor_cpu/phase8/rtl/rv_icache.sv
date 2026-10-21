// 8 KiB instruction-only cache: 1024 direct-mapped eight-byte lines.
// Two synchronous data banks provide an aligned instruction pair on a hit.
// The caller authorizes the whole line before asserting req_cacheable.
`timescale 1ns/1ps
module rv_icache (
    input wire clk, rst_n, invalidate,
    input wire req_valid,
    output wire req_ready,
    input wire [31:0] req_addr,
    input wire req_cacheable,
    output wire rsp_valid,
    input wire rsp_ready,
    output reg [31:0] rsp_data, rsp_second,
    output reg rsp_pair, rsp_err,
    output wire mem_req_valid,
    input wire mem_req_ready,
    output wire [31:0] mem_req_addr,
    input wire mem_rsp_valid,
    output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_data,
    input wire mem_rsp_err
);
    localparam IDLE=0, LOOKUP=1, SEND=2, WAIT_DATA=3, RESPONSE=4;
    reg [2:0] state;
    reg [31:0] address, first_data;
    reg cacheable, second, first_error, poisoned;
    reg [1023:0] valid;
    (* ram_style = "block" *) reg [31:0] even_data [0:1023];
    (* ram_style = "block" *) reg [31:0] odd_data [0:1023];
    (* ram_style = "block" *) reg [18:0] tags [0:1023];
    reg [31:0] even_q, odd_q;
    reg [18:0] tag_q;
    reg valid_q;
    wire [9:0] index = address[12:3];

    assign req_ready = state == IDLE && !invalidate && rst_n;
    assign rsp_valid = state == RESPONSE;
    assign mem_req_valid = state == SEND;
    assign mem_req_addr = cacheable ? {address[31:3], second, 2'b00} : address;
    assign mem_rsp_ready = state == WAIT_DATA;

    // No reset on the memories so Vivado can infer BRAM. Valid bits own reset.
    always @(posedge clk) begin
        if (req_valid && req_ready) begin
            even_q <= even_data[req_addr[12:3]];
            odd_q <= odd_data[req_addr[12:3]];
            tag_q <= tags[req_addr[12:3]];
        end
        if (state == WAIT_DATA && mem_rsp_valid && cacheable) begin
            if (second) odd_data[index] <= mem_rsp_data;
            else even_data[index] <= mem_rsp_data;
            if (second) tags[index] <= address[31:13];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            valid <= 0;
            valid_q <= 0;
            address <= 0;
            cacheable <= 0;
            second <= 0;
            first_data <= 0;
            first_error <= 0;
            poisoned <= 0;
            rsp_data <= 0;
            rsp_second <= 0;
            rsp_pair <= 0;
            rsp_err <= 0;
        end else begin
            case (state)
                IDLE: if (req_valid && req_ready) begin
                    address <= req_addr;
                    cacheable <= req_cacheable;
                    valid_q <= valid[req_addr[12:3]];
                    second <= 0;
                    poisoned <= 0;
                    rsp_pair <= 0;
                    rsp_err <= 0;
                    state <= req_cacheable ? LOOKUP : SEND;
                end
                LOOKUP: begin
                    if (valid_q && tag_q == address[31:13] && !invalidate) begin
                        rsp_data <= address[2] ? odd_q : even_q;
                        rsp_second <= odd_q;
                        rsp_pair <= !address[2];
                        state <= RESPONSE;
                    end else begin
                        valid[index] <= 0;
                        state <= SEND;
                    end
                end
                SEND: if (mem_req_ready) state <= WAIT_DATA;
                WAIT_DATA: if (mem_rsp_valid) begin
                    if (!cacheable) begin
                        rsp_data <= mem_rsp_data;
                        rsp_err <= mem_rsp_err;
                        state <= RESPONSE;
                    end else if (!second) begin
                        first_data <= mem_rsp_data;
                        first_error <= mem_rsp_err;
                        second <= 1;
                        state <= SEND;
                    end else begin
                        rsp_data <= address[2] ? mem_rsp_data : first_data;
                        rsp_second <= mem_rsp_data;
                        rsp_err <= address[2] ? mem_rsp_err : first_error;
                        rsp_pair <= !address[2] && !first_error && !mem_rsp_err;
                        valid[index] <= !first_error && !mem_rsp_err && !poisoned;
                        state <= RESPONSE;
                    end
                end
                RESPONSE: if (rsp_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
            // A fence may arrive during a refill. Drain it, but never revalidate
            // pre-fence bytes; the frontend kills the corresponding response.
            if (invalidate) begin
                valid <= 0;
                poisoned <= 1;
            end
        end
    end
endmodule
