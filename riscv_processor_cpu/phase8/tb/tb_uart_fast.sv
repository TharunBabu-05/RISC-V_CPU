`timescale 1ns/1ps
module tb_uart_fast;
    reg clk=0, rst_n=0, rx=1, valid=0;
    always #20 clk=~clk;
    reg [7:0] tx_data;
    wire tx, ready, rx_valid;
    wire [7:0] rx_data;
    integer received=0, transmitted=0;
    localparam real BIT_NS=1.0e9/921600.0;
    uart_tx #(.CLK_FREQ(25000000),.BAUD_RATE(921600)) transmitter
        (.clk(clk),.rst_n(rst_n),.i_data(tx_data),.i_valid(valid),.o_ready(ready),.o_tx(tx));
    uart_rx #(.CLK_FREQ(25000000),.BAUD_RATE(921600)) receiver
        (.clk(clk),.rst_n(rst_n),.i_rx(rx),.o_data(rx_data),.o_valid(rx_valid));
    always @(posedge clk) if(rst_n && rx_valid) begin
        if(rx_data !== received[7:0]) $fatal(1,"RX byte %0d got %h",received,rx_data);
        received=received+1;
    end
    // Host receiver uses exact 921600 timing, independent of the RTL divider.
    initial begin : host_rx
        reg [7:0] value;
        wait(rst_n);
        repeat(256) begin
            @(negedge tx);
            #(BIT_NS/2);
            if(tx!==0) $fatal(1,"TX start");
            for(integer b=0;b<8;b=b+1) begin #(BIT_NS); value[b]=tx; end
            #(BIT_NS);
            if(tx!==1 || value !== transmitted[7:0]) $fatal(1,"TX byte %0d got %h",transmitted,value);
            transmitted=transmitted+1;
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        fork
            begin
                #137;
                for(integer n=0;n<256;n=n+1) begin
                    rx=0; #(BIT_NS);
                    for(integer b=0;b<8;b=b+1) begin rx=(n>>b)&1; #(BIT_NS); end
                    rx=1; #(BIT_NS);
                end
            end
            begin
                for(integer n=0;n<256;n=n+1) begin
                    @(negedge clk);
                    while(!ready) @(negedge clk);
                    tx_data=n; valid=1;
                    @(negedge clk); valid=0;
                    wait(!ready);
                    wait(ready);
                end
            end
        join
        repeat(40) @(negedge clk);
        if(received!=256 || transmitted!=256) $fatal(1,"Lost bytes rx=%0d tx=%0d",received,transmitted);
        $display("PASS 921600 baud: all 256 byte values in both directions, independent host timing");
        $finish;
    end
    initial begin #10000000; $fatal(1,"UART timeout"); end
endmodule
