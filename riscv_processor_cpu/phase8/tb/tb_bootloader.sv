// End-to-end UART bootloader test.
// Loads a real RV32 binary through the serial pins, checks the CRC response,
// sends G, and verifies that the uploaded program prints APP:OK.
`timescale 1ns/1ps

module tb_bootloader;
    logic clk_12mhz = 1'b0;
    logic rst_btn = 1'b1;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic [3:0] led;

    localparam real CLK_HALF_NS = 41.667;
    localparam real BIT_NS = 217.0 * (2.0 * CLK_HALF_NS);
    localparam int MAX_APP_BYTES = 49152;

    byte app_bytes [0:MAX_APP_BYTES-1];
    integer app_size;
    integer app_file;
    string app_path;

    logic saw_idle = 1'b0;
    logic saw_ready = 1'b0;
    logic saw_header_ok = 1'b0;
    logic saw_upload_ok = 1'b0;
    logic saw_app_ok = 1'b0;
    logic next_line_active = 1'b0;
    integer next_count = 0;
    integer idle_index = 0;
    integer ready_index = 0;
    integer header_index = 0;
    integer upload_index = 0;
    integer app_index = 0;
    integer next_index = 0;

    always #CLK_HALF_NS clk_12mhz = ~clk_12mhz;

    soc_top dut (
        .clk_12mhz(clk_12mhz),
        .rst_btn  (rst_btn),
        .uart_tx  (uart_tx),
        .uart_rx  (uart_rx),
        .led      (led)
    );

    function automatic [31:0] crc32_byte(
        input [31:0] current_crc,
        input [7:0] data
    );
        reg [31:0] value;
        integer bit_index;
        begin
            value = current_crc ^ data;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                value = value[0] ? ((value >> 1) ^ 32'hEDB88320)
                                 :  (value >> 1);
            crc32_byte = value;
        end
    endfunction

    task automatic send_uart_byte(input [7:0] value);
        integer bit_index;
        begin
            uart_rx = 1'b0;
            #(BIT_NS);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = value[bit_index];
                #(BIT_NS);
            end
            uart_rx = 1'b1;
            #(BIT_NS);
        end
    endtask

    task automatic match_byte(
        input [7:0] value,
        input string pattern,
        inout integer index,
        inout logic matched
    );
        begin
            if (value == pattern[index]) begin
                if (index == pattern.len() - 1) begin
                    matched = 1'b1;
                    index = 0;
                end else begin
                    index = index + 1;
                end
            end else begin
                index = (value == pattern[0]) ? 1 : 0;
            end
        end
    endtask

    initial begin : uart_monitor
        reg [7:0] value;
        integer bit_index;
        forever begin
            @(negedge uart_tx);
            #(BIT_NS * 1.5);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx;
                #(BIT_NS);
            end
            $write("%c", value);
            match_byte(value, "RVBL:IDLE", idle_index, saw_idle);
            match_byte(value, "RVBL:READY", ready_index, saw_ready);
            match_byte(value, "RVBL:HEADER_OK", header_index, saw_header_ok);
            match_byte(value, "RVBL:OK", upload_index, saw_upload_ok);
            match_byte(value, "APP:OK", app_index, saw_app_ok);
            match_byte(value, "RVBL:NEXT ", next_index, next_line_active);
            if (next_line_active && value == 8'h0A) begin
                next_count = next_count + 1;
                next_line_active = 1'b0;
            end
        end
    end

    initial begin : test_sequence
        reg [31:0] crc;
        integer index;

        if (!$value$plusargs("APP_BIN=%s", app_path))
            app_path = "app.bin";
        app_file = $fopen(app_path, "rb");
        if (app_file == 0)
            $fatal(1, "Cannot open boot test application: %s", app_path);
        app_size = $fread(app_bytes, app_file);
        $fclose(app_file);
        if (app_size <= 0 || app_size > MAX_APP_BYTES)
            $fatal(1, "Invalid test application size: %0d", app_size);

        crc = 32'hFFFFFFFF;
        for (index = 0; index < app_size; index = index + 1)
            crc = crc32_byte(crc, app_bytes[index]);
        crc = crc ^ 32'hFFFFFFFF;

        #10_000;
        rst_btn = 1'b0;

        wait (saw_idle);
        send_uart_byte("U");
        wait (saw_ready);

        send_uart_byte("R");
        send_uart_byte("V");
        send_uart_byte("B");
        send_uart_byte("L");
        send_uart_byte(app_size[7:0]);
        send_uart_byte(app_size[15:8]);
        send_uart_byte(app_size[23:16]);
        send_uart_byte(app_size[31:24]);
        send_uart_byte(crc[7:0]);
        send_uart_byte(crc[15:8]);
        send_uart_byte(crc[23:16]);
        send_uart_byte(crc[31:24]);

        wait (saw_header_ok);
        begin : send_blocks
            integer block_start;
            integer block_end;
            integer acknowledged_blocks;
            block_start = 0;
            acknowledged_blocks = 0;
            while (block_start < app_size) begin
                block_end = block_start + 32;
                if (block_end > app_size)
                    block_end = app_size;
                for (index = block_start; index < block_end; index = index + 1)
                    send_uart_byte(app_bytes[index]);
                acknowledged_blocks = acknowledged_blocks + 1;
                wait (next_count >= acknowledged_blocks);
                block_start = block_end;
            end
        end

        wait (saw_upload_ok);
        send_uart_byte("G");
        wait (saw_app_ok);

        $display("\nPASS: UART image received, CRC verified, and application executed.");
        $finish;
    end

    initial begin
        #150_000_000;
        $fatal(1, "Timeout waiting for uploaded application");
    end
endmodule
