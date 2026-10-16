// ============================================================
//  dma_controller.sv - Single-channel memory-mapped DMA engine
//
//  Register map (relative to DMA base 0x1000_2000):
//    0x00 SRC_ADDR          Source byte address
//    0x04 DST_ADDR          Destination byte address
//    0x08 LENGTH            Transfer length in bytes
//    0x0C CONTROL           [0] start, [1] source increment,
//                           [2] destination increment,
//                           [4:3] width (0=8, 1=16, 2=32 bit),
//                           [5] interrupt enable, [6] abort
//    0x10 STATUS            [0] busy, [1] done, [2] error,
//                           [3] interrupt pending, [15:8] error code
//                           Write-one-to-clear bits [3:1].
//    0x14 TRANSFERRED       Bytes completed by the current/last transfer
//    0x18 ID                0x444D4131 ("DMA1")
//    0x1C REMAINING         Bytes not yet transferred
//
//  The master side uses request/grant handshaking. Reads complete later with
//  m_rvalid; writes complete when granted. The SoC arbiter gives the CPU
//  priority, allowing DMA to use otherwise-idle data-bus cycles.
// ============================================================
`timescale 1ns/1ps

module dma_controller (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [4:0]  s_addr,
    input  logic [31:0] s_wr_data,
    input  logic        s_wr_en,
    input  logic        s_rd_en,
    output logic [31:0] s_rd_data,

    output logic        m_req,
    output logic        m_write,
    output logic [31:0] m_addr,
    output logic [31:0] m_wdata,
    output logic [2:0]  m_funct3,
    input  logic        m_grant,
    input  logic        m_error,
    input  logic        m_rvalid,
    input  logic [31:0] m_rdata,

    output logic        irq
);
    localparam logic [4:0] REG_SRC         = 5'h00;
    localparam logic [4:0] REG_DST         = 5'h04;
    localparam logic [4:0] REG_LENGTH      = 5'h08;
    localparam logic [4:0] REG_CONTROL     = 5'h0C;
    localparam logic [4:0] REG_STATUS      = 5'h10;
    localparam logic [4:0] REG_TRANSFERRED = 5'h14;
    localparam logic [4:0] REG_ID          = 5'h18;
    localparam logic [4:0] REG_REMAINING   = 5'h1C;

    localparam logic [7:0] ERR_NONE        = 8'h00;
    localparam logic [7:0] ERR_BAD_WIDTH   = 8'h01;
    localparam logic [7:0] ERR_SELF_ACCESS = 8'h02;
    localparam logic [7:0] ERR_BUS         = 8'h03;
    localparam logic [7:0] ERR_ABORTED     = 8'h04;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_READ_REQUEST,
        ST_READ_WAIT,
        ST_WRITE_REQUEST
    } state_t;

    state_t state;
    logic [31:0] source_reg;
    logic [31:0] destination_reg;
    logic [31:0] length_reg;
    logic [5:1]  control_reg;

    logic [31:0] current_source;
    logic [31:0] current_destination;
    logic [31:0] remaining;
    logic [31:0] transferred;
    logic [31:0] read_buffer;
    logic [1:0]  width_latched;
    logic        source_increment;
    logic        destination_increment;
    logic        irq_enable_latched;
    logic        busy;
    logic        done;
    logic        error;
    logic        irq_pending;
    logic [7:0]  error_code;

    logic [2:0] beat_bytes;

    function automatic logic is_dma_address(input logic [31:0] address);
        is_dma_address = ((address & 32'hFFFF_FFE0) == 32'h1000_2000);
    endfunction

    always_comb begin
        case (width_latched)
            2'b00: beat_bytes = 3'd1;
            2'b01: beat_bytes = (remaining >= 2) ? 3'd2 : 3'd1;
            default: begin
                if (remaining >= 4)
                    beat_bytes = 3'd4;
                else if (remaining >= 2)
                    beat_bytes = 3'd2;
                else
                    beat_bytes = 3'd1;
            end
        endcase
    end

    always_comb begin
        m_req    = 1'b0;
        m_write  = 1'b0;
        m_addr   = 32'b0;
        m_wdata  = read_buffer;

        case (beat_bytes)
            3'd1: m_funct3 = 3'b000;
            3'd2: m_funct3 = 3'b001;
            default: m_funct3 = 3'b010;
        endcase

        if (state == ST_READ_REQUEST) begin
            m_req   = 1'b1;
            m_addr  = current_source;
        end else if (state == ST_WRITE_REQUEST) begin
            m_req   = 1'b1;
            m_write = 1'b1;
            m_addr  = current_destination;
        end
    end

    assign irq = irq_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                   <= ST_IDLE;
            source_reg              <= 32'b0;
            destination_reg         <= 32'b0;
            length_reg              <= 32'b0;
            control_reg             <= 5'b0;
            current_source          <= 32'b0;
            current_destination     <= 32'b0;
            remaining               <= 32'b0;
            transferred             <= 32'b0;
            read_buffer             <= 32'b0;
            width_latched           <= 2'b0;
            source_increment        <= 1'b0;
            destination_increment   <= 1'b0;
            irq_enable_latched      <= 1'b0;
            busy                    <= 1'b0;
            done                    <= 1'b0;
            error                   <= 1'b0;
            irq_pending             <= 1'b0;
            error_code              <= ERR_NONE;
        end else begin
            if (s_wr_en && !busy) begin
                case (s_addr)
                    REG_SRC: source_reg <= s_wr_data;
                    REG_DST: destination_reg <= s_wr_data;
                    REG_LENGTH: length_reg <= s_wr_data;
                    REG_CONTROL: control_reg <= s_wr_data[5:1];
                    default: ;
                endcase
            end

            if (s_wr_en && (s_addr == REG_STATUS)) begin
                if (s_wr_data[1])
                    done <= 1'b0;
                if (s_wr_data[2]) begin
                    error <= 1'b0;
                    error_code <= ERR_NONE;
                end
                if (s_wr_data[3])
                    irq_pending <= 1'b0;
            end

            // Abort is accepted while active; all other configuration writes
            // are ignored until the channel becomes idle.
            if (s_wr_en && (s_addr == REG_CONTROL) && s_wr_data[6] && busy) begin
                state       <= ST_IDLE;
                busy        <= 1'b0;
                error       <= 1'b1;
                error_code  <= ERR_ABORTED;
                irq_pending <= irq_enable_latched;
            end else if (s_wr_en && (s_addr == REG_CONTROL) &&
                         s_wr_data[0] && !busy) begin
                current_source        <= source_reg;
                current_destination   <= destination_reg;
                remaining             <= length_reg;
                transferred           <= 32'b0;
                width_latched         <= s_wr_data[4:3];
                source_increment      <= s_wr_data[1];
                destination_increment <= s_wr_data[2];
                irq_enable_latched    <= s_wr_data[5];
                done                  <= 1'b0;
                error                 <= 1'b0;
                irq_pending           <= 1'b0;
                error_code            <= ERR_NONE;

                if (s_wr_data[4:3] == 2'b11) begin
                    state       <= ST_IDLE;
                    busy        <= 1'b0;
                    error       <= 1'b1;
                    error_code  <= ERR_BAD_WIDTH;
                    irq_pending <= s_wr_data[5];
                end else if (is_dma_address(source_reg) ||
                             is_dma_address(destination_reg)) begin
                    state       <= ST_IDLE;
                    busy        <= 1'b0;
                    error       <= 1'b1;
                    error_code  <= ERR_SELF_ACCESS;
                    irq_pending <= s_wr_data[5];
                end else if (length_reg == 0) begin
                    state       <= ST_IDLE;
                    busy        <= 1'b0;
                    done        <= 1'b1;
                    irq_pending <= s_wr_data[5];
                end else begin
                    state <= ST_READ_REQUEST;
                    busy  <= 1'b1;
                end
            end else begin
                case (state)
                    ST_READ_REQUEST: begin
                        if (m_grant) begin
                            if (m_error) begin
                                state       <= ST_IDLE;
                                busy        <= 1'b0;
                                error       <= 1'b1;
                                error_code  <= ERR_BUS;
                                irq_pending <= irq_enable_latched;
                            end else begin
                                state <= ST_READ_WAIT;
                            end
                        end
                    end

                    ST_READ_WAIT: begin
                        if (m_rvalid) begin
                            read_buffer <= m_rdata;
                            state <= ST_WRITE_REQUEST;
                        end
                    end

                    ST_WRITE_REQUEST: begin
                        if (m_grant) begin
                            if (m_error) begin
                                state       <= ST_IDLE;
                                busy        <= 1'b0;
                                error       <= 1'b1;
                                error_code  <= ERR_BUS;
                                irq_pending <= irq_enable_latched;
                            end else begin
                                transferred <= transferred + beat_bytes;
                                remaining <= remaining - beat_bytes;
                                if (source_increment)
                                    current_source <= current_source + beat_bytes;
                                if (destination_increment)
                                    current_destination <= current_destination + beat_bytes;

                                if (remaining <= beat_bytes) begin
                                    state       <= ST_IDLE;
                                    busy        <= 1'b0;
                                    done        <= 1'b1;
                                    irq_pending <= irq_enable_latched;
                                end else begin
                                    state <= ST_READ_REQUEST;
                                end
                            end
                        end
                    end

                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        s_rd_data = 32'b0;
        if (s_rd_en) begin
            case (s_addr)
                REG_SRC:         s_rd_data = source_reg;
                REG_DST:         s_rd_data = destination_reg;
                REG_LENGTH:      s_rd_data = length_reg;
                REG_CONTROL:     s_rd_data = {26'b0, control_reg, 1'b0};
                REG_STATUS:      s_rd_data = {16'b0, error_code, 4'b0,
                                              irq_pending, error, done, busy};
                REG_TRANSFERRED: s_rd_data = transferred;
                REG_ID:          s_rd_data = 32'h444D_4131;
                REG_REMAINING:   s_rd_data = remaining;
                default:         s_rd_data = 32'b0;
            endcase
        end
    end
endmodule
