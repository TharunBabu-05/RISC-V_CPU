// ============================================================
//  dcache.sv  –  Data cache wrapper (pass-through)
// ============================================================
`timescale 1ns/1ps

module dcache #(
    parameter int XLEN = 32,
    parameter int LINES = 16,
    parameter int MISS_PENALTY = 3
) (
    input  logic        clk,
    input  logic [XLEN-1:0] addr,
    input  logic [XLEN-1:0] wr_data,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [2:0]  funct3,
    output logic [XLEN-1:0] rd_data,
    output logic        stall,
    input  logic        ptw_read,
    input  logic [XLEN-1:0] ptw_addr,
    output logic [31:0] ptw_rdata
);

    localparam int LINE_BYTES  = (XLEN / 8);
    localparam int OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int INDEX_BITS  = $clog2(LINES);
    localparam int TAG_BITS    = XLEN - OFFSET_BITS - INDEX_BITS;
    localparam logic [2:0] FILL_FUNCT3 = (XLEN == 64) ? 3'b011 : 3'b010; // LD or LW

    typedef enum logic [1:0] {DC_IDLE, DC_WAIT, DC_FILL} dc_state_t;
    dc_state_t state;

    logic [XLEN-1:0] data [0:LINES-1];
    logic [TAG_BITS-1:0] tags [0:LINES-1];
    logic [LINES-1:0] valid;

    logic [INDEX_BITS-1:0] req_index;
    logic [TAG_BITS-1:0]   req_tag;
    logic                 hit;

    logic [XLEN-1:0] miss_addr;
    logic [XLEN-1:0] miss_wr_data;
    logic            miss_mem_read;
    logic            miss_mem_write;
    logic [2:0]      miss_funct3;
    int unsigned     miss_cnt;

    logic [INDEX_BITS-1:0] fill_index;
    logic [TAG_BITS-1:0]   fill_tag;
    logic [XLEN-1:0]       fill_line;
    logic [XLEN-1:0]       fill_line_update;

    // L2 interface
    logic [XLEN-1:0] l2_addr;
    logic [XLEN-1:0] l2_wr_data;
    logic            l2_mem_read;
    logic            l2_mem_write;
    logic [2:0]      l2_funct3;
    logic [XLEN-1:0] l2_rd_data;

    l2_cache #(.XLEN(XLEN)) u_l2 (
        .clk      (clk),
        .addr     (l2_addr),
        .wr_data  (l2_wr_data),
        .mem_read (l2_mem_read),
        .mem_write(l2_mem_write),
        .funct3   (l2_funct3),
        .rd_data  (l2_rd_data),
        .ptw_read (ptw_read),
        .ptw_addr (ptw_addr),
        .ptw_rdata(ptw_rdata)
    );

    assign req_index = addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
    assign req_tag   = addr[XLEN-1 : OFFSET_BITS + INDEX_BITS];
    assign hit       = valid[req_index] && (tags[req_index] == req_tag);

    assign fill_index = miss_addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
    assign fill_tag   = miss_addr[XLEN-1 : OFFSET_BITS + INDEX_BITS];

    function automatic logic [XLEN-1:0] store_merge(
        input logic [XLEN-1:0] line,
        input logic [XLEN-1:0] addr_in,
        input logic [2:0]      f3,
        input logic [XLEN-1:0] wdata
    );
        logic [XLEN-1:0] out;
        begin
            out = line;
            if (XLEN == 32) begin
                case (f3)
                    3'b000: begin // SB
                        case (addr_in[1:0])
                            2'b00: out[7:0]   = wdata[7:0];
                            2'b01: out[15:8]  = wdata[7:0];
                            2'b10: out[23:16] = wdata[7:0];
                            2'b11: out[31:24] = wdata[7:0];
                            default: out = line;
                        endcase
                    end
                    3'b001: begin // SH
                        case (addr_in[1])
                            1'b0: out[15:0]  = wdata[15:0];
                            1'b1: out[31:16] = wdata[15:0];
                            default: out = line;
                        endcase
                    end
                    3'b010: out = wdata[31:0]; // SW
                    default: out = wdata[31:0];
                endcase
            end else begin
                case (f3)
                    3'b000: begin // SB
                        case (addr_in[2:0])
                            3'b000: out[7:0]   = wdata[7:0];
                            3'b001: out[15:8]  = wdata[7:0];
                            3'b010: out[23:16] = wdata[7:0];
                            3'b011: out[31:24] = wdata[7:0];
                            3'b100: out[39:32] = wdata[7:0];
                            3'b101: out[47:40] = wdata[7:0];
                            3'b110: out[55:48] = wdata[7:0];
                            3'b111: out[63:56] = wdata[7:0];
                            default: out = line;
                        endcase
                    end
                    3'b001: begin // SH
                        case (addr_in[2:1])
                            2'b00: out[15:0]  = wdata[15:0];
                            2'b01: out[31:16] = wdata[15:0];
                            2'b10: out[47:32] = wdata[15:0];
                            2'b11: out[63:48] = wdata[15:0];
                            default: out = line;
                        endcase
                    end
                    3'b010: begin // SW
                        case (addr_in[2])
                            1'b0: out[31:0]  = wdata[31:0];
                            1'b1: out[63:32] = wdata[31:0];
                            default: out = line;
                        endcase
                    end
                    3'b011: out = wdata[63:0]; // SD
                    default: out = wdata[63:0];
                endcase
            end
            store_merge = out;
        end
    endfunction

    function automatic logic [XLEN-1:0] load_extract(
        input logic [XLEN-1:0] line,
        input logic [XLEN-1:0] addr_in,
        input logic [2:0]      f3
    );
        logic [7:0]  b;
        logic [15:0] h;
        logic [31:0] w;
        begin
            if (XLEN == 32) begin
                case (addr_in[1:0])
                    2'b00: b = line[7:0];
                    2'b01: b = line[15:8];
                    2'b10: b = line[23:16];
                    2'b11: b = line[31:24];
                    default: b = 8'b0;
                endcase
                case (addr_in[1])
                    1'b0: h = line[15:0];
                    1'b1: h = line[31:16];
                    default: h = 16'b0;
                endcase
                w = line[31:0];
                case (f3)
                    3'b000: load_extract = {{24{b[7]}}, b};
                    3'b001: load_extract = {{16{h[15]}}, h};
                    3'b010: load_extract = w;
                    3'b100: load_extract = {24'b0, b};
                    3'b101: load_extract = {16'b0, h};
                    default: load_extract = w;
                endcase
            end else begin
                case (addr_in[2:0])
                    3'b000: b = line[7:0];
                    3'b001: b = line[15:8];
                    3'b010: b = line[23:16];
                    3'b011: b = line[31:24];
                    3'b100: b = line[39:32];
                    3'b101: b = line[47:40];
                    3'b110: b = line[55:48];
                    3'b111: b = line[63:56];
                    default: b = 8'b0;
                endcase
                case (addr_in[2:1])
                    2'b00: h = line[15:0];
                    2'b01: h = line[31:16];
                    2'b10: h = line[47:32];
                    2'b11: h = line[63:48];
                    default: h = 16'b0;
                endcase
                case (addr_in[2])
                    1'b0: w = line[31:0];
                    1'b1: w = line[63:32];
                    default: w = 32'b0;
                endcase
                case (f3)
                    3'b000: load_extract = {{56{b[7]}}, b};
                    3'b001: load_extract = {{48{h[15]}}, h};
                    3'b010: load_extract = {{32{w[31]}}, w};
                    3'b011: load_extract = line;
                    3'b100: load_extract = {56'b0, b};
                    3'b101: load_extract = {48'b0, h};
                    3'b110: load_extract = {32'b0, w};
                    default: load_extract = line;
                endcase
            end
        end
    endfunction

    assign fill_line = l2_rd_data;
    assign fill_line_update = miss_mem_write
        ? store_merge(fill_line, miss_addr, miss_funct3, miss_wr_data)
        : fill_line;

    // Combinational outputs
    always_comb begin
        rd_data = {XLEN{1'b0}};
        if (state == DC_IDLE && hit && mem_read)
            rd_data = load_extract(data[req_index], addr, funct3);
    end

    // Miss detection and stall
    assign stall = (state != DC_IDLE) || (mem_read && !hit);

    // L2 control
    always_comb begin
        l2_addr      = {XLEN{1'b0}};
        l2_wr_data   = {XLEN{1'b0}};
        l2_mem_read  = 1'b0;
        l2_mem_write = 1'b0;
        l2_funct3    = FILL_FUNCT3;

        if (state == DC_IDLE) begin
            if (mem_write) begin
                l2_addr      = addr;
                l2_wr_data   = wr_data;
                l2_mem_write = 1'b1;
                l2_funct3    = funct3;
            end
        end else if (state == DC_FILL) begin
            l2_addr     = miss_addr;
            l2_mem_read = 1'b1;
            l2_mem_write= miss_mem_write;
            l2_wr_data  = fill_line_update;
            l2_funct3   = miss_mem_write ? miss_funct3 : FILL_FUNCT3;
        end
    end

    // Cache state updates
    integer i;
    initial begin
        valid = {LINES{1'b0}};
        for (i = 0; i < LINES; i = i + 1) begin
            data[i] = {XLEN{1'b0}};
            tags[i] = {TAG_BITS{1'b0}};
        end
        state = DC_IDLE;
        miss_cnt = 0;
    end

    always_ff @(posedge clk) begin
        case (state)
            DC_IDLE: begin
                if (mem_write) begin
                    data[req_index]  <= store_merge(hit ? data[req_index] : l2_rd_data, addr, funct3, wr_data);
                    tags[req_index]  <= req_tag;
                    valid[req_index] <= 1'b1;
                end

                if (mem_read && !hit) begin
                    miss_addr      <= addr;
                    miss_wr_data   <= wr_data;
                    miss_mem_read  <= mem_read;
                    miss_mem_write <= mem_write;
                    miss_funct3    <= funct3;
                    if (MISS_PENALTY > 0) begin
                        miss_cnt <= MISS_PENALTY - 1;
                        state    <= DC_WAIT;
                    end else begin
                        state <= DC_FILL;
                    end
                end
            end
            DC_WAIT: begin
                if (miss_cnt == 0) begin
                    state <= DC_FILL;
                end else begin
                    miss_cnt <= miss_cnt - 1;
                end
            end
            DC_FILL: begin
                data[fill_index]  <= fill_line_update;
                tags[fill_index]  <= fill_tag;
                valid[fill_index] <= 1'b1;
                state             <= DC_IDLE;
            end
            default: state <= DC_IDLE;
        endcase
    end

endmodule
