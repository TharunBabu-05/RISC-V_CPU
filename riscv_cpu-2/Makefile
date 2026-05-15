SIM_DIR  := sim
RTL_DIR  := rtl
TB_DIR   := tb

SRCS := \
	$(RTL_DIR)/alu.sv          \
	$(RTL_DIR)/muldiv.sv       \
	$(RTL_DIR)/regfile.sv      \
	$(RTL_DIR)/imm_gen.sv      \
	$(RTL_DIR)/csr_file.sv     \
	$(RTL_DIR)/interrupt_unit.sv \
	$(RTL_DIR)/branch_predictor.sv \
	$(RTL_DIR)/fp_regfile.sv   \
	$(RTL_DIR)/fpu_unit.sv     \
	$(RTL_DIR)/vector_regfile.sv \
	$(RTL_DIR)/vector_unit.sv  \
	$(RTL_DIR)/control_unit.sv \
	$(RTL_DIR)/hazard.sv       \
	$(RTL_DIR)/memory.sv       \
	$(RTL_DIR)/dram_ctrl.sv    \
	$(RTL_DIR)/l2_cache.sv     \
	$(RTL_DIR)/dcache.sv       \
	$(RTL_DIR)/icache.sv       \
	$(RTL_DIR)/mmu.sv          \
	$(RTL_DIR)/cpu_top.sv      \
	$(TB_DIR)/tb_cpu.sv

VVP := $(SIM_DIR)/cpu_sim
VCD := $(SIM_DIR)/cpu_wave.vcd
VVP_MULDIV := $(SIM_DIR)/cpu_sim_muldiv
VVP_BRANCH := $(SIM_DIR)/cpu_sim_branch
VVP_RV64 := $(SIM_DIR)/cpu_sim_rv64
VVP_MMU := $(SIM_DIR)/cpu_sim_mmu
VVP_FP := $(SIM_DIR)/cpu_sim_fp
VVP_VEC := $(SIM_DIR)/cpu_sim_vector

SRCS_MULDIV := \
	$(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) \
	$(TB_DIR)/tb_muldiv.sv

SRCS_BRANCH := \
	$(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) \
	$(TB_DIR)/tb_branch_edge.sv

SRCS_RV64 := \
	$(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) \
	$(TB_DIR)/tb_cpu64.sv

SRCS_MMU := \
	$(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) \
	$(TB_DIR)/tb_mmu.sv

SRCS_FP := \
	$(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) \
	$(TB_DIR)/tb_fp.sv

SRCS_VEC := \
	$(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) \
	$(TB_DIR)/tb_vector.sv

.PHONY: all sim sim_muldiv sim_branch_edge sim_rv64 sim_mmu sim_fp sim_vector build-sim lint wave clean phase5 phase5-checklist phase5-compliance phase5-formal phase5-synthesis

all: sim

build-sim:
	mkdir -p $(SIM_DIR)

sim: build-sim
	iverilog -g2012 -I$(RTL_DIR) -o $(VVP) $(SRCS)
	cd $(SIM_DIR) && vvp cpu_sim

sim_muldiv: build-sim
	iverilog -g2012 -I$(RTL_DIR) -o $(VVP_MULDIV) $(SRCS_MULDIV)
	cd $(SIM_DIR) && vvp cpu_sim_muldiv

sim_branch_edge: build-sim
	iverilog -g2012 -I$(RTL_DIR) -o $(VVP_BRANCH) $(SRCS_BRANCH)
	cd $(SIM_DIR) && vvp cpu_sim_branch

sim_rv64: build-sim
	iverilog -g2012 -I$(RTL_DIR) -o $(VVP_RV64) $(SRCS_RV64)
	cd $(SIM_DIR) && vvp cpu_sim_rv64

sim_mmu: build-sim
	iverilog -g2012 -I$(RTL_DIR) -o $(VVP_MMU) $(SRCS_MMU)
	cd $(SIM_DIR) && vvp cpu_sim_mmu

sim_fp: build-sim
	iverilog -g2012 -I$(RTL_DIR) -o $(VVP_FP) $(SRCS_FP)
	cd $(SIM_DIR) && vvp cpu_sim_fp

sim_vector: build-sim
	iverilog -g2012 -I$(RTL_DIR) -o $(VVP_VEC) $(SRCS_VEC)
	cd $(SIM_DIR) && vvp cpu_sim_vector

lint:
	verilator --lint-only -Wall --top-module cpu_top $(SRCS)

wave: sim
	gtkwave $(VCD) &

clean:
	rm -f $(VVP) $(VCD)

phase5:
	@$(MAKE) phase5-checklist
	@$(MAKE) phase5-compliance
	@$(MAKE) phase5-formal
	@$(MAKE) phase5-synthesis

phase5-checklist:
	@echo Phase 5 checklist:
	@echo   docs/phase5_checklist.md
	@echo   docs/production_plan.md
	@echo   README.md

phase5-compliance:
	@echo Phase 5 handoff artifacts:
	@echo   docs/phase5_compliance.md
	@echo   phase5/compliance/README.md
	@echo   phase5/compliance/rv32i.profile
	@echo   phase5/compliance/rv32im.profile
	@echo   phase5/compliance/rv64i.profile
	@echo   phase5/compliance/rv64im.profile

phase5-formal:
	@echo Phase 5 formal artifacts:
	@echo   docs/phase5_formal_verification.md
	@echo   phase5/formal/README.md
	@echo   phase5/formal/pipeline_control.sby
	@echo   phase5/formal/hazard_checks.sby
	@echo   phase5/formal/csr_checks.sby

phase5-synthesis:
	@echo Phase 5 synthesis artifacts:
	@echo   docs/phase5_synthesis.md
	@echo   phase5/synthesis/README.md
	@echo   phase5/synthesis/core_constraints.tcl

phase5-compliance-run:
	python phase5/compliance/run_rv32_compliance.py
