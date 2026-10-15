IVERILOG ?= iverilog
VVP ?= vvp
BUILD := build
SOC_RTL := ../rtl
CPU_RTL := ../../rtl

CPU_SRCS := \
	$(CPU_RTL)/alu.sv \
	$(CPU_RTL)/branch_predictor.sv \
	$(CPU_RTL)/control_unit.sv \
	$(CPU_RTL)/hazard.sv \
	$(CPU_RTL)/imm_gen.sv \
	$(CPU_RTL)/interrupt_unit.sv \
	$(CPU_RTL)/regfile.sv \
	$(CPU_RTL)/pmp_unit.sv \
	$(CPU_RTL)/muldiv.sv \
	$(CPU_RTL)/csr_file.sv

SOC_SRCS := \
	$(SOC_RTL)/soc_top.sv \
	$(SOC_RTL)/bram.sv \
	$(SOC_RTL)/uart.sv \
	$(SOC_RTL)/uart_tx.sv \
	$(SOC_RTL)/uart_rx.sv \
	$(SOC_RTL)/clint.sv \
	$(SOC_RTL)/plic.sv \
	$(SOC_RTL)/cpu_top_soc.sv \
	$(CPU_SRCS)

.PHONY: all clint plic interrupt_sources interrupt_map clean

all: clint plic interrupt_sources interrupt_map

$(BUILD):
	mkdir -p $(BUILD)

clint: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_clint -o $(BUILD)/tb_clint tb_clint.sv $(SOC_RTL)/clint.sv
	$(VVP) $(BUILD)/tb_clint

plic: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_plic -o $(BUILD)/tb_plic tb_plic.sv $(SOC_RTL)/plic.sv
	$(VVP) $(BUILD)/tb_plic

interrupt_sources: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_interrupt_sources -o $(BUILD)/tb_interrupt_sources \
		tb_interrupt_sources.sv $(CPU_RTL)/interrupt_unit.sv
	$(VVP) $(BUILD)/tb_interrupt_sources

interrupt_map: | $(BUILD)
	$(IVERILOG) -g2012 -DSIMULATION -s tb_interrupt_map \
		-o $(BUILD)/tb_interrupt_map tb_interrupt_map.sv $(SOC_SRCS)
	cd $(SOC_RTL) && $(VVP) ../tb/$(BUILD)/tb_interrupt_map

clean:
	rm -rf $(BUILD)
