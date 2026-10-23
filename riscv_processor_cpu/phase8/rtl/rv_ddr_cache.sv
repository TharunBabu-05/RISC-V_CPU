// Shared 8 KiB DDR cache: 2048 direct-mapped four-byte lines.
// Write-through, no write allocation. Shared placement or external ownership
// barriers must keep other DDR masters coherent with the cached CPU view.
// Bus data/strobes are right-justified at the exact byte address.
`timescale 1ns/1ps
module rv_ddr_cache #(
    parameter logic [31:0] BASE_ADDR = 32'h80000000,
    parameter logic [31:0] SIZE_BYTES = 32'h10000000,
    parameter bit FAST_HIT = 0
) (
    input wire clk, rst_n, invalidate,
    output wire idle,
    input wire req_valid,
    output wire req_ready,
    input wire [31:0] req_addr, req_wdata,
    input wire req_write,
    input wire [3:0] req_wstrb,
    input wire [1:0] req_size,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire [31:0] rsp_rdata,
    output wire rsp_err,
    output wire mem_req_valid,
    input wire mem_req_ready,
    output wire [31:0] mem_req_addr, mem_req_wdata,
    output wire mem_req_write,
    output wire [3:0] mem_req_wstrb,
    output wire [1:0] mem_req_size,
    input wire mem_rsp_valid,
    output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata,
    input wire mem_rsp_err
);
    localparam IDLE=0, LOOKUP=1, SEND=2, WAIT_DATA=3, RESPONSE=4;
    reg [2:0] state;
    reg [2047:0] valid;
    (* ram_style = "block" *) reg [31:0] data [0:2047];
    (* ram_style = "block" *) reg [18:0] tags [0:2047];
    reg [31:0] data_q, address, write_data;
    reg [31:0] response_data;
    reg response_error;
    reg [18:0] tag_q;
    reg valid_q, write_req, cacheable, write_hit, poisoned;
    reg [3:0] strobes;
    reg [1:0] size;
    wire [2:0] request_bytes = req_size == 0 ? 1 : req_size == 1 ? 2 : 4;
    wire fits_word = {1'b0,req_addr[1:0]} + request_bytes <= 4;
    wire in_range = req_addr >= BASE_ADDR && req_size != 3 &&
        {1'b0,req_addr[31:2],2'b00} >= {1'b0,BASE_ADDR} &&
        ({1'b0,req_addr[31:2],2'b00} + 33'd4 <= {1'b0,BASE_ADDR}+{1'b0,SIZE_BYTES});
    wire strobes_valid = !req_write || (({1'b0,req_wstrb} >> request_bytes) == 0);
    wire overlaps_ddr = {1'b0,req_addr} < {1'b0,BASE_ADDR}+{1'b0,SIZE_BYTES} &&
        {1'b0,req_addr}+request_bytes > {1'b0,BASE_ADDR};
    wire hit = valid_q && tag_q == address[31:13] && !poisoned && !invalidate;
    wire [31:0] read_mask = size == 0 ? 32'hff : size == 1 ? 32'hffff : 32'hffffffff;
    wire [31:0] shifted_read = data_q >> (address[1:0]*8);
    wire [3:0] lane_mask = strobes << address[1:0];
    wire [31:0] lane_data = write_data << (address[1:0]*8);
    reg [31:0] merged;
    always @* begin
        merged = data_q;
        for (integer b=0;b<4;b=b+1)
            if (lane_mask[b]) merged[b*8+:8] = lane_data[b*8+:8];
    end
    assign req_ready = rst_n && state == IDLE && !invalidate;
    assign idle = state == IDLE;
    wire direct_hit = FAST_HIT && state == LOOKUP && cacheable && !write_req && hit;
    assign rsp_valid = state == RESPONSE || direct_hit;
    assign rsp_rdata = direct_hit ? shifted_read & read_mask : response_data;
    assign rsp_err = direct_hit ? 1'b0 : response_error;
    assign mem_req_valid = state == SEND;
    assign mem_req_addr = cacheable && !write_req ? {address[31:2],2'b00} : address;
    assign mem_req_size = cacheable && !write_req ? 2'd2 : size;
    assign mem_req_write = write_req;
    assign mem_req_wdata = write_data;
    assign mem_req_wstrb = strobes;
    assign mem_rsp_ready = state == WAIT_DATA;

    // No memory resets: validity owns reset and invalidation, allowing BRAM.
    always @(posedge clk) begin
        if (req_valid && req_ready) begin
            data_q <= data[req_addr[12:2]];
            tag_q <= tags[req_addr[12:2]];
        end
        if (state == WAIT_DATA && mem_rsp_valid && !mem_rsp_err &&
            cacheable && !poisoned && !invalidate && (!write_req || write_hit)) begin
            data[address[12:2]] <= write_req ? merged : mem_rsp_rdata;
            tags[address[12:2]] <= address[31:13];
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; valid <= 0; valid_q <= 0;
            address <= 0; write_data <= 0; strobes <= 0; size <= 0;
            write_req <= 0; cacheable <= 0; write_hit <= 0; poisoned <= 0;
            response_data <= 0; response_error <= 0;
        end else begin
            case (state)
                IDLE: if (req_valid && req_ready) begin
                    address <= req_addr; write_data <= req_wdata;
                    strobes <= req_wstrb; size <= req_size; write_req <= req_write;
                    cacheable <= in_range && fits_word && strobes_valid;
                    valid_q <= valid[req_addr[12:2]];
                    poisoned <= 0; write_hit <= 0; response_error <= 0;
                    state <= LOOKUP;
                    // Bypassed/cross-word stores may change either line, even
                    // on a partial downstream failure. Conservatively flush.
                    if (req_write && overlaps_ddr && !(in_range && fits_word && strobes_valid))
                        valid <= 0;
                end
                LOOKUP: begin
                    if (cacheable && !write_req && hit) begin
                        response_data <= shifted_read & read_mask;
                        state <= FAST_HIT && rsp_ready ? IDLE : RESPONSE;
                    end else begin
                        write_hit <= cacheable && write_req && hit;
                        if (cacheable) valid[address[12:2]] <= 0;
                        state <= SEND;
                    end
                end
                SEND: if (mem_req_ready) state <= WAIT_DATA;
                WAIT_DATA: if (mem_rsp_valid) begin
                    response_error <= mem_rsp_err;
                    response_data <= write_req ? 0 : cacheable ?
                        ((mem_rsp_rdata >> (address[1:0]*8)) & read_mask) : mem_rsp_rdata;
                    if (cacheable && !poisoned && !invalidate && !mem_rsp_err &&
                        (!write_req || write_hit)) valid[address[12:2]] <= 1;
                    state <= RESPONSE;
                end
                RESPONSE: if (rsp_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
            if (invalidate) begin valid <= 0; poisoned <= 1; end
        end
    end
endmodule
