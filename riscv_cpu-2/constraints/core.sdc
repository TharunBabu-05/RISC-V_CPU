create_clock -name core_clk -period 10.000 [get_ports clk]
set_input_delay  2.0 -clock core_clk [all_inputs]
set_output_delay 2.0 -clock core_clk [all_outputs]
set_false_path -from [get_ports rst_n]
