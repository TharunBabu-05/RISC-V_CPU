// ============================================================
//  branch_predictor.sv  –  2-bit BHT + BTB branch predictor
// ============================================================
`timescale 1ns/1ps

module branch_predictor #(
    parameter int XLEN = 32,
    parameter int BTB_ENTRIES = 16
) (
    input  logic              clk,
    input  logic              rst_n,

    // Fetch query
    input  logic [XLEN-1:0]   pc_fetch,
    output logic              predict_valid,
    output logic              predict_taken,
    output logic [XLEN-1:0]   predict_target,

    // Update from EX stage
    input  logic              update,
    input  logic [XLEN-1:0]   pc_update,
    input  logic              actual_taken,
    input  logic [XLEN-1:0]   actual_target
);

    localparam int IDX_BITS = $clog2(BTB_ENTRIES);
    localparam int TAG_BITS = XLEN - IDX_BITS - 2;

    logic [BTB_ENTRIES-1:0] valid;
    logic [TAG_BITS-1:0]    tags   [0:BTB_ENTRIES-1];
    logic [XLEN-1:0]        target [0:BTB_ENTRIES-1];
    logic [1:0]             bht    [0:BTB_ENTRIES-1];

    logic [IDX_BITS-1:0] idx_fetch;
    logic [IDX_BITS-1:0] idx_update;
    logic [TAG_BITS-1:0] tag_fetch;
    logic [TAG_BITS-1:0] tag_update;
    logic btb_hit;

    assign idx_fetch  = pc_fetch[IDX_BITS+1:2];
    assign idx_update = pc_update[IDX_BITS+1:2];
    assign tag_fetch  = pc_fetch[XLEN-1:IDX_BITS+2];
    assign tag_update = pc_update[XLEN-1:IDX_BITS+2];

    assign btb_hit = valid[idx_fetch] && (tags[idx_fetch] == tag_fetch);
    assign predict_valid  = btb_hit;
    assign predict_taken  = btb_hit && bht[idx_fetch][1];
    assign predict_target = target[idx_fetch];

    // Reset/init
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= {BTB_ENTRIES{1'b0}};
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                tags[i]   <= {TAG_BITS{1'b0}};
                target[i] <= {XLEN{1'b0}};
                bht[i]    <= 2'b01; // weakly not taken
            end
        end else if (update) begin
            valid[idx_update] <= 1'b1;
            tags[idx_update]  <= tag_update;
            target[idx_update] <= actual_target;
            case (bht[idx_update])
                2'b00: bht[idx_update] <= actual_taken ? 2'b01 : 2'b00;
                2'b01: bht[idx_update] <= actual_taken ? 2'b10 : 2'b00;
                2'b10: bht[idx_update] <= actual_taken ? 2'b11 : 2'b01;
                2'b11: bht[idx_update] <= actual_taken ? 2'b11 : 2'b10;
                default: bht[idx_update] <= 2'b01;
            endcase
        end
    end

endmodule
