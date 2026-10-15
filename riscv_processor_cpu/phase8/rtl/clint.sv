// ============================================================
//  clint.sv - Single-hart Core-Local Interruptor
//
//  Relative register map (CLINT base 0x0200_0000):
//    0x0000       msip       bit 0: machine software interrupt
//    0x4000       mtimecmp    low 32 bits
//    0x4004       mtimecmp    high 32 bits
//    0xBFF8       mtime       low 32 bits
//    0xBFFC       mtime       high 32 bits
// ============================================================
`timescale 1ns/1ps

module clint (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] addr,
    input  logic [31:0] wr_data,
    input  logic        wr_en,
    input  logic        rd_en,
    output logic [31:0] rd_data,
    output logic        software_irq,
    output logic        timer_irq
);
    localparam logic [15:0] MSIP_ADDR      = 16'h0000;
    localparam logic [15:0] MTIMECMP_LO    = 16'h4000;
    localparam logic [15:0] MTIMECMP_HI    = 16'h4004;
    localparam logic [15:0] MTIME_LO       = 16'hBFF8;
    localparam logic [15:0] MTIME_HI       = 16'hBFFC;

    logic        msip;
    logic [63:0] mtime;
    logic [63:0] mtimecmp;

    assign software_irq = msip;
    assign timer_irq = (mtime >= mtimecmp);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip     <= 1'b0;
            mtime    <= 64'b0;
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
        end else begin
            mtime <= mtime + 64'd1;

            if (wr_en) begin
                case (addr)
                    MSIP_ADDR:   msip           <= wr_data[0];
                    MTIMECMP_LO: mtimecmp[31:0] <= wr_data;
                    MTIMECMP_HI: mtimecmp[63:32] <= wr_data;
                    MTIME_LO:    mtime[31:0]    <= wr_data;
                    MTIME_HI:    mtime[63:32]   <= wr_data;
                    default: begin end
                endcase
            end
        end
    end

    always_comb begin
        rd_data = 32'b0;
        if (rd_en) begin
            case (addr)
                MSIP_ADDR:   rd_data = {31'b0, msip};
                MTIMECMP_LO: rd_data = mtimecmp[31:0];
                MTIMECMP_HI: rd_data = mtimecmp[63:32];
                MTIME_LO:    rd_data = mtime[31:0];
                MTIME_HI:    rd_data = mtime[63:32];
                default:     rd_data = 32'b0;
            endcase
        end
    end
endmodule
