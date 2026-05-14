`timescale 1ns/1ps

module phase5_properties (
    input logic clk,
    input logic rst_n
);
    logic rst_seen;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rst_seen <= 1'b1;
        else        rst_seen <= rst_seen;
    end

    default clocking cb @(posedge clk); endclocking

    property p_reset_seen_before_run;
        rst_n |-> rst_seen;
    endproperty

    assert property (p_reset_seen_before_run);
endmodule
