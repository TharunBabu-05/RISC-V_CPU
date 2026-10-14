// ============================================================
//  l2_cache.sv - Direct-mapped write-through L2 cache
// ============================================================
`timescale 1ns/1ps

module l2_cache #(
    parameter int XLEN = 32,
    parameter int LINES = 64
) (
    input  logic            clk,
    input  logic [XLEN-1:0] addr,
    input  logic [XLEN-1:0] wr_data,
    input  logic            mem_read,
    input  logic            mem_write,
    input  logic [2:0]      funct3,
    output logic [XLEN-1:0] rd_data,
    input  logic            ptw_read,
    input  logic [XLEN-1:0] ptw_addr,
    output logic [31:0]     ptw_rdata
);
    localparam int LINE_BYTES = XLEN / 8;
    localparam int OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int INDEX_BITS = $clog2(LINES);
    localparam int TAG_BITS = XLEN - OFFSET_BITS - INDEX_BITS;
    localparam logic [2:0] FULL_FUNCT3 = (XLEN == 64) ? 3'b011 : 3'b010;

    logic [XLEN-1:0] data [0:LINES-1];
    logic [TAG_BITS-1:0] tags [0:LINES-1];
    logic [LINES-1:0] valid;
    logic [INDEX_BITS-1:0] index, next_index;
    logic [TAG_BITS-1:0] tag, next_tag;
    logic [XLEN-1:0] next_addr;
    logic hit, next_hit, aligned, cacheable_read;
    logic [XLEN-1:0] dram_rd_data;
    logic [31:0] hit_count, miss_count;
    integer i;

    dram_ctrl #(.XLEN(XLEN)) u_dram (
        .clk(clk), .addr(addr), .wr_data(wr_data),
        .mem_read(mem_read), .mem_write(mem_write), .funct3(funct3),
        .rd_data(dram_rd_data), .ptw_read(ptw_read), .ptw_addr(ptw_addr),
        .ptw_rdata(ptw_rdata)
    );

    assign index = addr[OFFSET_BITS + INDEX_BITS - 1:OFFSET_BITS];
    assign tag = addr[XLEN-1:OFFSET_BITS + INDEX_BITS];
    assign next_addr = addr + LINE_BYTES;
    assign next_index = next_addr[OFFSET_BITS + INDEX_BITS - 1:OFFSET_BITS];
    assign next_tag = next_addr[XLEN-1:OFFSET_BITS + INDEX_BITS];
    assign hit = valid[index] && tags[index] == tag;
    assign next_hit = valid[next_index] && tags[next_index] == next_tag;
    assign aligned = (addr[OFFSET_BITS-1:0] == 0);
    assign cacheable_read = mem_read && aligned && funct3 == FULL_FUNCT3;

    // A miss is read-through because the legacy L1/L2 interface is
    // combinational. The fetched line is installed at the next clock edge.
    assign rd_data = mem_read ? ((cacheable_read && hit) ? data[index] : dram_rd_data)
                              : {XLEN{1'b0}};

    function automatic logic [XLEN-1:0] merge_store(
        input logic [XLEN-1:0] line,
        input logic [XLEN-1:0] byte_addr,
        input logic [2:0]      width,
        input logic [XLEN-1:0] value
    );
        logic [XLEN-1:0] result;
        integer bytes, n;
        begin
            result = line;
            case (width[1:0])
                2'b00: bytes = 1;
                2'b01: bytes = 2;
                2'b10: bytes = 4;
                default: bytes = LINE_BYTES;
            endcase
            for (n = 0; n < LINE_BYTES; n = n + 1)
                if (n < bytes && (byte_addr[OFFSET_BITS-1:0] + n) < LINE_BYTES)
                    result[(byte_addr[OFFSET_BITS-1:0] + n)*8 +: 8] = value[n*8 +: 8];
            merge_store = result;
        end
    endfunction

    initial begin
        valid = {LINES{1'b0}};
        hit_count = 0;
        miss_count = 0;
        for (i = 0; i < LINES; i = i + 1) begin
            data[i] = {XLEN{1'b0}};
            tags[i] = {TAG_BITS{1'b0}};
        end
    end

    always_ff @(posedge clk) begin
        if (cacheable_read) begin
            if (hit) begin
                hit_count <= hit_count + 1;
            end else begin
                miss_count <= miss_count + 1;
                data[index] <= dram_rd_data;
                tags[index] <= tag;
                valid[index] <= 1'b1;
            end
        end

        if (mem_write) begin
            if (hit && aligned)
                data[index] <= merge_store(data[index], addr, funct3, wr_data);
            else if (aligned && funct3 == FULL_FUNCT3) begin
                data[index] <= wr_data;
                tags[index] <= tag;
                valid[index] <= 1'b1;
            end else begin
                // A cross-line store updates backing memory directly. Drop any
                // resident copies touched by it so later loads cannot be stale.
                if (hit)
                    valid[index] <= 1'b0;
                if (next_hit)
                    valid[next_index] <= 1'b0;
            end
        end
    end
endmodule
