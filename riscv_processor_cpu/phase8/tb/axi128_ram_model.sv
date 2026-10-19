// Simulation only. Independent AXI channel stalls and delayed responses.
// Models 64 KiB, a 4 KiB DDR app stack, plus address probes of 256 MiB RAM.
`timescale 1ns/1ps
module axi128_ram_model (
    input wire clk, rst_n,
    input wire inject_read_error, inject_write_error,
    input wire [3:0] axi_awid,
    input wire [27:0] axi_awaddr,
    input wire [7:0] axi_awlen,
    input wire [2:0] axi_awsize,
    input wire [1:0] axi_awburst,
    input wire axi_awlock,
    input wire [3:0] axi_awcache,
    input wire [2:0] axi_awprot,
    input wire [3:0] axi_awqos,
    input wire axi_awvalid,
    output logic axi_awready,
    input wire [127:0] axi_wdata,
    input wire [15:0] axi_wstrb,
    input wire axi_wlast,
    input wire axi_wvalid,
    output logic axi_wready,
    output logic [3:0] axi_bid,
    output logic [1:0] axi_bresp,
    output logic axi_bvalid,
    input wire axi_bready,
    input wire [3:0] axi_arid,
    input wire [27:0] axi_araddr,
    input wire [7:0] axi_arlen,
    input wire [2:0] axi_arsize,
    input wire [1:0] axi_arburst,
    input wire axi_arlock,
    input wire [3:0] axi_arcache,
    input wire [2:0] axi_arprot,
    input wire [3:0] axi_arqos,
    input wire axi_arvalid,
    output logic axi_arready,
    output logic [3:0] axi_rid,
    output logic [127:0] axi_rdata,
    output logic [1:0] axi_rresp,
    output logic axi_rlast,
    output logic axi_rvalid,
    input wire axi_rready
);
    reg [127:0] mem [0:4383];
    reg have_aw, have_w, reading;
    reg [27:0] write_addr, read_addr;
    reg [127:0] write_data;
    reg [15:0] write_strb;
    integer cycles, delay_read, delay_write;
    integer write_count = 0, read_count = 0;
    integer i;
    initial for (i=0; i<4384; i=i+1) mem[i] = 0;
    function automatic integer index_of(input [27:0] address);
        integer k;
        begin
            index_of = -1;
            if (address < 28'h10000) index_of = address >> 4;
            else if (address == 28'hFFFFFF0) index_of = 4096;
            else if (address >= 28'hFF000 && address < 28'h100000)
                index_of = 4128 + ((address - 28'hFF000) >> 4);
            else for (k=16; k<28; k=k+1)
                if (address == (28'd1 << k)) index_of = 4097+k-16;
            if (index_of < 0) $fatal(1,"RAM model has no storage for %h",address);
        end
    endfunction
    assign axi_awready = rst_n && !have_aw && !axi_bvalid && delay_write == 0 && cycles%5 == 1;
    assign axi_wready = rst_n && !have_w && !axi_bvalid && delay_write == 0 && cycles%7 == 2;
    assign axi_arready = rst_n && !reading && !axi_rvalid && cycles%3 == 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycles <= 0; have_aw <= 0; have_w <= 0; reading <= 0;
            delay_read <= 0; delay_write <= 0;
            axi_bvalid <= 0; axi_bresp <= 0; axi_bid <= 0;
            axi_rvalid <= 0; axi_rresp <= 0; axi_rid <= 0;
            axi_rlast <= 1; axi_rdata <= 0;
        end else begin
            cycles <= cycles+1;
            if (axi_awvalid && axi_awready) begin
                if (axi_awaddr[3:0] || axi_awsize != 4 || axi_awlen != 0 || axi_awburst != 1)
                    $fatal(1,"Invalid MIG write shape");
                have_aw <= 1; write_addr <= axi_awaddr;
            end
            if (axi_wvalid && axi_wready) begin
                if (!axi_wlast) $fatal(1,"Missing WLAST");
                have_w <= 1; write_data <= axi_wdata; write_strb <= axi_wstrb;
            end
            if (have_aw && have_w && delay_write == 0) begin
                have_aw <= 0; have_w <= 0; delay_write <= 5;
                write_count <= write_count+1;
                if (!inject_write_error)
                    for (integer lane=0; lane<16; lane=lane+1)
                        if (write_strb[lane])
                            mem[index_of(write_addr)][lane*8+:8] <= write_data[lane*8+:8];
                axi_bresp <= inject_write_error ? 2'b10 : 2'b00;
            end
            if (delay_write > 0) begin
                delay_write <= delay_write-1;
                if (delay_write == 1) axi_bvalid <= 1;
            end
            if (axi_bvalid && axi_bready) axi_bvalid <= 0;
            if (axi_arvalid && axi_arready) begin
                if (axi_araddr[3:0] || axi_arsize != 4 || axi_arlen != 0 || axi_arburst != 1)
                    $fatal(1,"Invalid MIG read shape");
                reading <= 1; read_addr <= axi_araddr; delay_read <= 7;
                read_count <= read_count+1;
            end
            if (reading) begin
                delay_read <= delay_read-1;
                if (delay_read == 1) begin
                    axi_rdata <= mem[index_of(read_addr)];
                    axi_rvalid <= 1; axi_rresp <= inject_read_error ? 2'b10 : 2'b00;
                    reading <= 0;
                end
            end
            if (axi_rvalid && axi_rready) axi_rvalid <= 0;
        end
    end
endmodule

