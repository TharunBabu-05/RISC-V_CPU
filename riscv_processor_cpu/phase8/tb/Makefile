IVERILOG ?= iverilog
VVP ?= vvp
DDR_CPU_ARGS ?=
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
	$(CPU_RTL)/mmu.sv \
	$(CPU_RTL)/regfile.sv \
	$(CPU_RTL)/pmp_unit.sv \
	$(CPU_RTL)/muldiv.sv \
	$(CPU_RTL)/csr_file.sv

SOC_SRCS := \
	$(SOC_RTL)/soc_core_txn.sv \
	$(SOC_RTL)/rv_bus_arbiter.sv \
	$(SOC_RTL)/soc_top.sv \
	$(SOC_RTL)/generic_fpga_top.sv \
	$(SOC_RTL)/bram.sv \
	$(SOC_RTL)/uart.sv \
	$(SOC_RTL)/uart_tx.sv \
	$(SOC_RTL)/uart_rx.sv \
	$(SOC_RTL)/clint.sv \
	$(SOC_RTL)/plic.sv \
	$(SOC_RTL)/dma_controller.sv \
	$(SOC_RTL)/qspi_reader.sv \
	$(SOC_RTL)/cpu_top_soc.sv \
	$(SOC_RTL)/rv_icache.sv \
	$(SOC_RTL)/rv_pair_alu.sv \
	$(CPU_SRCS)

.PHONY: all boot_regress boot_banner clint plic dma dma_soc qspi qspi_boot qspi_corrupt uart_recovery interrupt_sources interrupt_map portable clean

all: clint plic dma dma_soc qspi interrupt_sources interrupt_map portable

boot_regress: boot_banner qspi_boot qspi_corrupt uart_recovery

$(BUILD):
	mkdir -p $(BUILD)

boot_banner: | $(BUILD)
	$(IVERILOG) -g2012 -DSIMULATION -s tb_boot_banner \
		-o $(BUILD)/tb_boot_banner tb_boot_banner.sv $(SOC_SRCS)
	cd $(SOC_RTL) && $(VVP) ../tb/$(BUILD)/tb_boot_banner

clint: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_clint -o $(BUILD)/tb_clint tb_clint.sv $(SOC_RTL)/clint.sv
	$(VVP) $(BUILD)/tb_clint

plic: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_plic -o $(BUILD)/tb_plic tb_plic.sv $(SOC_RTL)/plic.sv
	$(VVP) $(BUILD)/tb_plic

dma: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_dma_controller -o $(BUILD)/tb_dma_controller \
		tb_dma_controller.sv $(SOC_RTL)/dma_controller.sv
	$(VVP) $(BUILD)/tb_dma_controller

dma_soc: | $(BUILD)
	$(IVERILOG) -g2012 -DSIMULATION -s tb_dma_soc \
		-o $(BUILD)/tb_dma_soc tb_dma_soc.sv $(SOC_SRCS)
	cd $(SOC_RTL) && $(VVP) ../tb/$(BUILD)/tb_dma_soc

qspi: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_qspi_reader -o $(BUILD)/tb_qspi_reader \
		tb_qspi_reader.sv $(SOC_RTL)/qspi_reader.sv
	$(VVP) $(BUILD)/tb_qspi_reader

$(BUILD)/tb_qspi_boot: tb_qspi_boot.sv $(SOC_SRCS) | $(BUILD)
	$(IVERILOG) -g2012 -DSIMULATION -s tb_qspi_boot \
		-o $(BUILD)/tb_qspi_boot tb_qspi_boot.sv $(SOC_SRCS)

qspi_boot: $(BUILD)/tb_qspi_boot
	$(VVP) $(BUILD)/tb_qspi_boot \
		+FLASH_BIN=../software/build/boot_test_flash.bin

qspi_corrupt: $(BUILD)/tb_qspi_boot
	$(VVP) $(BUILD)/tb_qspi_boot \
		+FLASH_BIN=../software/build/boot_test_flash.bin +CORRUPT_CRC

uart_recovery: | $(BUILD)
	$(IVERILOG) -g2012 -DSIMULATION -s tb_bootloader \
		-o $(BUILD)/tb_uart_recovery tb_bootloader.sv $(SOC_SRCS)
	$(VVP) $(BUILD)/tb_uart_recovery \
		+APP_BIN=../software/build/boot_test_app.bin

interrupt_sources: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_interrupt_sources -o $(BUILD)/tb_interrupt_sources \
		tb_interrupt_sources.sv $(CPU_RTL)/interrupt_unit.sv
	$(VVP) $(BUILD)/tb_interrupt_sources

interrupt_map: | $(BUILD)
	$(IVERILOG) -g2012 -DSIMULATION -s tb_interrupt_map \
		-o $(BUILD)/tb_interrupt_map tb_interrupt_map.sv $(SOC_SRCS)
	cd $(SOC_RTL) && $(VVP) ../tb/$(BUILD)/tb_interrupt_map

portable: | $(BUILD)
	$(IVERILOG) -g2012 -DPORTABLE_BUILD -s generic_fpga_top \
		-o $(BUILD)/portable_elaboration $(SOC_SRCS)
	$(IVERILOG) -g2012 -DSIMULATION -s tb_portable_soc \
		-o $(BUILD)/tb_portable_soc tb_portable_soc.sv $(SOC_SRCS)
	cd $(SOC_RTL) && $(VVP) ../tb/$(BUILD)/tb_portable_soc

clean:
	rm -rf $(BUILD)

.PHONY: axi128 ddr_soc ddr
axi128: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_axi128 -o $(BUILD)/tb_axi128 \
		tb_axi128.sv axi128_ram_model.sv $(SOC_RTL)/rv_bus_to_axi128.sv
	$(VVP) $(BUILD)/tb_axi128

ddr_soc: | $(BUILD)
	$(MAKE) -C ../software ddr_test
	$(IVERILOG) -g2012 -DSIMULATION $(DDR_CPU_ARGS) -s tb_ddr_soc -o $(BUILD)/tb_ddr_soc \
		tb_ddr_soc.sv axi128_ram_model.sv $(SOC_RTL)/rv_bus_to_axi128.sv $(SOC_SRCS)
	$(VVP) $(BUILD)/tb_ddr_soc

ddr: axi128 ddr_soc

.PHONY: ddr_loader_sim
ddr_loader_sim: | $(BUILD)
	$(MAKE) -C ../software ddr_loader ddr_app_test
	$(IVERILOG) -g2012 -DSIMULATION $(DDR_CPU_ARGS) -s tb_ddr_soc -Ptb_ddr_soc.LOADER_MODE=1 \
		-Ptb_ddr_soc.FIRMWARE_FILE=\"../software/build/ddr_loader.vmem\" \
		-o $(BUILD)/tb_ddr_loader tb_ddr_soc.sv axi128_ram_model.sv \
		$(SOC_RTL)/rv_bus_to_axi128.sv $(SOC_SRCS)
	$(VVP) $(BUILD)/tb_ddr_loader $(DDR_LOADER_SIM_ARGS)

.PHONY: ddr_loader_deferred
ddr_loader_deferred:
	$(MAKE) ddr_loader_sim DDR_LOADER_SIM_ARGS=+DEFERRED_RUN

.PHONY: ddr_wad_sim
ddr_wad_sim:
	$(MAKE) -C ../software ddr_wad_test ddr_wad_fixture
	$(MAKE) ddr_loader_sim DDR_LOADER_SIM_ARGS=+WAD_TEST

.PHONY: ddr_wad_probe_sim
ddr_wad_probe_sim:
	$(MAKE) -C ../software ddr_wad_probe ddr_wad_fixture
	$(MAKE) ddr_loader_sim DDR_LOADER_SIM_ARGS=+WAD_PROBE

.PHONY: ddr_fast_wad_sim
ddr_fast_wad_sim:
	$(MAKE) -C ../software ddr_wad_probe build/ddr_fast_test.wad
	$(MAKE) ddr_loader_sim DDR_LOADER_SIM_ARGS=+FAST_WAD

.PHONY: icache ddr_perf_sim
icache: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_icache -o $(BUILD)/tb_icache tb_icache.sv $(SOC_RTL)/rv_icache.sv
	$(VVP) $(BUILD)/tb_icache

ddr_perf_sim:
	$(MAKE) ddr_soc DDR_CPU_ARGS="-Ptb_ddr_soc.ENABLE_ICACHE=1 -Ptb_ddr_soc.DUAL_ISSUE=1 -Ptb_ddr_soc.UART_BAUD=921600"

.PHONY: dual_issue uart_fast
uart_fast: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_uart_fast -o $(BUILD)/tb_uart_fast tb_uart_fast.sv $(SOC_RTL)/uart_tx.sv $(SOC_RTL)/uart_rx.sv
	$(VVP) $(BUILD)/tb_uart_fast

dual_issue: | $(BUILD)
	$(IVERILOG) -g2012 -s tb_dual_issue -o $(BUILD)/tb_dual_issue tb_dual_issue.sv $(SOC_SRCS)
	$(VVP) $(BUILD)/tb_dual_issue
	$(VVP) $(BUILD)/tb_dual_issue +SEED=42
	$(VVP) $(BUILD)/tb_dual_issue +SEED=2026
	$(IVERILOG) -g2012 -s tb_dual_issue -Ptb_dual_issue.DUAL=0 -o $(BUILD)/tb_single_issue tb_dual_issue.sv $(SOC_SRCS)
	$(VVP) $(BUILD)/tb_single_issue
	$(IVERILOG) -g2012 -s tb_dual_issue -Ptb_dual_issue.CACHE=0 -o $(BUILD)/tb_uncached tb_dual_issue.sv $(SOC_SRCS)
	$(VVP) $(BUILD)/tb_uncached
