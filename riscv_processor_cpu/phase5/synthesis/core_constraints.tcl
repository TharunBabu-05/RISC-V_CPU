# 100 MHz baseline for Phase 5 handoff
create_clock -name core_clk -period 10.000 [get_ports clk]

# Integration-specific IO delays should be tuned per board or SoC wrapper.
set_input_delay  2.0 -clock core_clk [all_inputs]
set_output_delay 2.0 -clock core_clk [all_outputs]

# Reset is modeled as asynchronous assertion with synchronous release in integration.
set_false_path -from [get_ports rst_n]