# MIG's calibration/reset signals cross into the 25 MHz CPU clock domain.
# The first ready synchronizer stage may metastabilize; the later stages
# resolve it before memory_ready is used. Check those later stages normally.
set ddr_ready_first [get_pins -quiet -hierarchical -regexp {.*ready_pipe_reg\[0\]/D$}]
set_false_path -to $ddr_ready_first

# ui_clk_sync_rst asynchronously asserts the AXI converter reset. Its
# deassertion is synchronized by axi_sys_reset_pipe in clk_sys; recovery
# checks at the asynchronous clear pins are not synchronous timing paths.
set ddr_cpu_reset_pins [get_pins -quiet -hierarchical -regexp {.*axi_sys_reset_pipe_reg\[[0-3]\]/CLR$}]
set_false_path -to $ddr_cpu_reset_pins
