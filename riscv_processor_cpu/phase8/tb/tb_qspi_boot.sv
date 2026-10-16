// End-to-end flash boot test: read RVF1 image, verify CRC, copy to BRAM, run.
`timescale 1ns/1ps

module tb_qspi_boot;
    logic clk_12mhz = 1'b0;
    logic rst_btn = 1'b1;
    logic uart_rx = 1'b1;
    logic uart_tx;
    logic [3:0] led;
    logic qspi_cs;
    tri [3:0] qspi_dq;

    logic qspi_miso = 1'b1;
    logic qspi_miso_enable = 1'b0;
    byte flash_image [0:65535];
    integer flash_size;
    integer flash_file;
    string flash_path;
    integer tx_bits = 0;
    integer rx_bits = 0;
    logic [31:0] tx_word = 32'b0;
    logic [7:0] response_byte = 8'hFF;

    logic saw_flash_ok = 1'b0;
    logic saw_flash_crc_error = 1'b0;
    logic saw_idle = 1'b0;
    logic saw_no_image = 1'b0;
    logic saw_app_ok = 1'b0;
    integer flash_ok_index = 0;
    integer flash_crc_index = 0;
    integer idle_index = 0;
    integer no_image_index = 0;
    integer app_ok_index = 0;
    logic corrupt_crc = 1'b0;

    localparam integer FLASH_OFFSET = 24'h400000;
    localparam real CLK_HALF_NS = 41.667;
    localparam real UART_BIT_NS = 217.0 * (2.0 * CLK_HALF_NS);

    always #CLK_HALF_NS clk_12mhz = ~clk_12mhz;
    assign qspi_dq[1] = qspi_miso_enable ? qspi_miso : 1'bz;

    soc_top #(
        .FIRMWARE_FILE("../software/build/bootloader.vmem")
    ) dut (
        .clk_12mhz(clk_12mhz),
        .rst_btn(rst_btn),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx),
        .qspi_cs(qspi_cs),
        .qspi_dq(qspi_dq),
        .led(led)
    );

    always @(negedge qspi_cs) begin
        tx_bits = 0;
        rx_bits = 0;
        tx_word = 32'b0;
        qspi_miso_enable = 1'b0;
    end

    always @(posedge qspi_cs)
        qspi_miso_enable = 1'b0;

    always @(posedge dut.qspi_sck) begin
        if (!qspi_cs && tx_bits < 32) begin
            tx_word = {tx_word[30:0], qspi_dq[0]};
            tx_bits = tx_bits + 1;
        end
    end

    always @(negedge dut.qspi_sck) begin : flash_response
        integer image_index;
        if (!qspi_cs && tx_bits == 32 && rx_bits < 8) begin
            if (rx_bits == 0) begin
                if (tx_word[31:24] != 8'h03)
                    $fatal(1, "Unexpected flash command %02x", tx_word[31:24]);
                image_index = tx_word[23:0] - FLASH_OFFSET;
                response_byte = (image_index >= 0 && image_index < flash_size)
                              ? flash_image[image_index] : 8'hFF;
            end
            qspi_miso_enable = 1'b1;
            qspi_miso = response_byte[7-rx_bits];
            rx_bits = rx_bits + 1;
        end
    end

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
                end else
                    index = index + 1;
            end else
                index = (value == pattern[0]) ? 1 : 0;
        end
    endtask

    task automatic send_uart_byte(input [7:0] value);
        integer bit_index;
        begin
            uart_rx = 1'b0;
            #(UART_BIT_NS);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = value[bit_index];
                #(UART_BIT_NS);
            end
            uart_rx = 1'b1;
            #(UART_BIT_NS);
        end
    endtask

    initial begin : uart_monitor
        reg [7:0] value;
        integer bit_index;
        forever begin
            @(negedge uart_tx);
            #(UART_BIT_NS * 1.5);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx;
                #(UART_BIT_NS);
            end
            $write("%c", value);
            match_byte(value, "RVBL:FLASH_OK", flash_ok_index, saw_flash_ok);
            match_byte(value, "RVBL:FLASH_INVALID CRC", flash_crc_index,
                       saw_flash_crc_error);
            match_byte(value, "RVBL:IDLE", idle_index, saw_idle);
            match_byte(value, "RVBL:ERR NO_IMAGE", no_image_index,
                       saw_no_image);
            match_byte(value, "APP:OK", app_ok_index, saw_app_ok);
        end
    end

    initial begin
        if (!$value$plusargs("FLASH_BIN=%s", flash_path))
            flash_path = "../software/build/boot_test_flash.bin";
        flash_file = $fopen(flash_path, "rb");
        if (!flash_file)
            $fatal(1, "Cannot open flash image: %s", flash_path);
        flash_size = $fread(flash_image, flash_file);
        $fclose(flash_file);
        corrupt_crc = $test$plusargs("CORRUPT_CRC");
        if (corrupt_crc)
            flash_image[flash_size-1] = flash_image[flash_size-1] ^ 8'h01;

        #10_000;
        rst_btn = 1'b0;
        if (corrupt_crc) begin
            wait (saw_flash_crc_error);
            wait (saw_idle);
            send_uart_byte("G");
            wait (saw_no_image);
            if (saw_app_ok)
                $fatal(1, "Corrupt QSPI image was executed");
            $display("\nPASS: corrupt QSPI payload rejected; UART recovery entered and blocked execution.");
        end else begin
            wait (saw_flash_ok);
            wait (saw_app_ok);
            $display("\nPASS: valid QSPI image copied to BRAM and executed automatically.");
        end
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "Timeout waiting for QSPI application boot");
    end
endmodule
