// Four ordered posted DDR writes. Reads and MMIO wait for the queue to drain.
// A delayed write error latches fault until reset; integration must fail-stop
// CPU accesses and invalidate local cached data, not silently retry stores.
`timescale 1ns/1ps
module rv_write_buffer #(
    parameter bit ENABLE = 1,
    parameter [31:0] BASE_ADDR = 32'h80000000,
    parameter [31:0] SIZE_BYTES = 32'h10000000
) (
    input wire clk, rst_n,
    input wire req_valid, output wire req_ready,
    input wire [31:0] req_addr, req_wdata,
    input wire req_write, input wire [3:0] req_wstrb, input wire [1:0] req_size,
    output reg rsp_valid, input wire rsp_ready,
    output reg [31:0] rsp_rdata, output reg rsp_err,
    output wire mem_req_valid, input wire mem_req_ready,
    output wire [31:0] mem_req_addr, mem_req_wdata,
    output wire mem_req_write, output wire [3:0] mem_req_wstrb,
    output wire [1:0] mem_req_size,
    input wire mem_rsp_valid, output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata, input wire mem_rsp_err,
    output wire idle, output reg fault, output reg [31:0] fault_addr
);
    reg [31:0] addresses[0:3], values[0:3];
    reg [3:0] strobes[0:3];
    reg [1:0] sizes[0:3], head, tail;
    reg [2:0] count;
    localparam IDLE=0, STORE_SEND=1, STORE_WAIT=2, DIRECT_SEND=3, DIRECT_WAIT=4;
    reg [2:0] state;
    reg [31:0] direct_addr, direct_data;
    reg direct_write;
    reg [3:0] direct_strobes;
    reg [1:0] direct_size;
    wire [2:0] bytes = req_size==0 ? 1 : req_size==1 ? 2 : 4;
    wire postable = ENABLE && req_write && req_size != 3 &&
        req_addr >= BASE_ADDR &&
        {1'b0,req_addr}+bytes <= {1'b0,BASE_ADDR}+{1'b0,SIZE_BYTES} &&
        ({1'b0,req_wstrb} >> bytes)==0;
    wire direct_active = state==DIRECT_SEND || state==DIRECT_WAIT;
    assign req_ready = rst_n && !rsp_valid && !direct_active &&
        (fault || (postable ? count<4 : count==0 && state==IDLE));
    wire push = req_valid && req_ready && postable && !fault;
    wire pop = state==STORE_WAIT && mem_rsp_valid;
    assign idle = count==0 && state==IDLE && !rsp_valid;
    assign mem_req_valid = !fault && (state==STORE_SEND || state==DIRECT_SEND);
    assign mem_req_addr = state==DIRECT_SEND ? direct_addr : addresses[head];
    assign mem_req_wdata = state==DIRECT_SEND ? direct_data : values[head];
    assign mem_req_write = state==DIRECT_SEND ? direct_write : 1'b1;
    assign mem_req_wstrb = state==DIRECT_SEND ? direct_strobes : strobes[head];
    assign mem_req_size = state==DIRECT_SEND ? direct_size : sizes[head];
    assign mem_rsp_ready = state==STORE_WAIT || state==DIRECT_WAIT;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            head<=0; tail<=0; count<=0; state<=IDLE;
            rsp_valid<=0; rsp_rdata<=0; rsp_err<=0; fault<=0; fault_addr<=0;
            direct_addr<=0; direct_data<=0; direct_write<=0; direct_strobes<=0; direct_size<=0;
        end else begin
            if(rsp_valid && rsp_ready) rsp_valid<=0;
            case({push,pop})
                2'b10: count<=count+1;
                2'b01: count<=count-1;
                default: ;
            endcase
            if(req_valid && req_ready) begin
                rsp_rdata<=0; rsp_err<=fault;
                if(fault) rsp_valid<=1;
                else if(postable) begin
                    addresses[tail]<=req_addr; values[tail]<=req_wdata;
                    strobes[tail]<=req_wstrb; sizes[tail]<=req_size;
                    tail<=tail+1; rsp_valid<=1;
                end else begin
                    direct_addr<=req_addr; direct_data<=req_wdata;
                    direct_write<=req_write; direct_strobes<=req_wstrb; direct_size<=req_size;
                    state<=DIRECT_SEND;
                end
            end
            case(state)
                IDLE: if(count!=0 && !fault) state<=STORE_SEND;
                STORE_SEND: if(mem_req_ready) state<=STORE_WAIT;
                STORE_WAIT: if(mem_rsp_valid) begin
                    head<=head+1; state<=IDLE;
                    if(mem_rsp_err) begin fault<=1; fault_addr<=addresses[head]; end
                end
                DIRECT_SEND: if(mem_req_ready) state<=DIRECT_WAIT;
                DIRECT_WAIT: if(mem_rsp_valid) begin
                    rsp_rdata<=mem_rsp_rdata; rsp_err<=mem_rsp_err;
                    rsp_valid<=1; state<=IDLE;
                end
                default: ;
            endcase
        end
    end
endmodule
