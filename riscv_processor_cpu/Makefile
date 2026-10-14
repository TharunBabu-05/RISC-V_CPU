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
	$(RTL_DIR)/pmp_unit.sv     \
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

.PHONY: regress compliance formal verify phase6-all sim_p6_alu sim_p6_hazards sim_p6_control
.PHONY: all sim sim_muldiv sim_muldiv_unit sim_fpu_unit sim_vector_unit sim_csr_forward sim_dcache_store sim_branch_predict sim_irq_precise sim_trap sim_mem_stall sim_rv64_jalr sim_mmu_unit sim_branch_edge sim_rv64 sim_mmu sim_fp sim_vector build-sim lint wave clean \
         phase5-formal phase5-synthesis phase5-all phase5-compliance-run phase5-clean

all: sim

build-sim:
	mkdir -p $(SIM_DIR)

sim: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP) $(SRCS)
	cd $(SIM_DIR) && vvp cpu_sim

sim_muldiv: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_MULDIV) $(SRCS_MULDIV)
	cd $(SIM_DIR) && vvp cpu_sim_muldiv

sim_muldiv_unit: build-sim
	iverilog -g2012 -o $(SIM_DIR)/muldiv_unit $(RTL_DIR)/muldiv.sv $(TB_DIR)/tb_muldiv_unit.sv
	cd $(SIM_DIR) && vvp muldiv_unit

sim_csr_forward: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(SIM_DIR)/csr_forward $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) $(TB_DIR)/tb_csr_forward.sv
	cd $(SIM_DIR) && vvp csr_forward

sim_dcache_store: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(SIM_DIR)/dcache_store $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) $(TB_DIR)/tb_dcache_store.sv
	cd $(SIM_DIR) && vvp dcache_store

sim_branch_predict: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(SIM_DIR)/branch_predict $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) $(TB_DIR)/tb_branch_predict.sv
	cd $(SIM_DIR) && vvp branch_predict

sim_irq_precise: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(SIM_DIR)/irq_precise $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) $(TB_DIR)/tb_irq_precise.sv
	cd $(SIM_DIR) && vvp irq_precise

sim_trap: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(SIM_DIR)/trap $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) $(TB_DIR)/tb_trap.sv
	cd $(SIM_DIR) && vvp trap

sim_mem_stall: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(SIM_DIR)/mem_stall $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) $(TB_DIR)/tb_mem_stall.sv
	cd $(SIM_DIR) && vvp mem_stall

sim_rv64_jalr: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(SIM_DIR)/rv64_jalr $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) $(TB_DIR)/tb_rv64_jalr.sv
	cd $(SIM_DIR) && vvp rv64_jalr

sim_btb_stale: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(SIM_DIR)/btb_stale $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS)) $(TB_DIR)/tb_btb_stale.sv
	cd $(SIM_DIR) && vvp btb_stale

sim_mmu_unit: build-sim
	iverilog -g2012 -o $(SIM_DIR)/mmu_unit $(RTL_DIR)/mmu.sv $(TB_DIR)/tb_mmu_unit.sv
	cd $(SIM_DIR) && vvp mmu_unit

# Unit tests against bit-exact Python reference models (vectors generated first)
sim_fpu_unit: build-sim
	python $(TB_DIR)/fpu_ref.py selftest
	python $(TB_DIR)/fpu_ref.py vectors $(SIM_DIR)/fpu_vectors.txt
	iverilog -g2012 -o $(SIM_DIR)/fpu_unit $(RTL_DIR)/fpu_unit.sv $(TB_DIR)/tb_fpu_unit.sv
	cd $(SIM_DIR) && vvp fpu_unit +VECTORS=fpu_vectors.txt

sim_vector_unit: build-sim
	python $(TB_DIR)/vec_ref.py vectors $(SIM_DIR)/vec_vectors.txt
	iverilog -g2012 -o $(SIM_DIR)/vector_unit $(RTL_DIR)/vector_unit.sv $(TB_DIR)/tb_vector_unit.sv
	cd $(SIM_DIR) && vvp vector_unit +VECTORS=vec_vectors.txt

sim_branch_edge: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_BRANCH) $(SRCS_BRANCH)
	cd $(SIM_DIR) && vvp cpu_sim_branch

sim_rv64: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_RV64) $(SRCS_RV64)
	cd $(SIM_DIR) && vvp cpu_sim_rv64

sim_mmu: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_MMU) $(SRCS_MMU)
	cd $(SIM_DIR) && vvp cpu_sim_mmu

sim_fp: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_FP) $(SRCS_FP)
	cd $(SIM_DIR) && vvp cpu_sim_fp

sim_vector: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_VEC) $(SRCS_VEC)
	cd $(SIM_DIR) && vvp cpu_sim_vector

lint:
	verilator --lint-only -Wall --top-module cpu_top $(SRCS)

wave: sim
	gtkwave $(VCD) &

clean:
	rm -f $(VVP) $(VCD)

# ============================================================
#  Verification entry points (each fails if anything fails)
# ============================================================
# All directed and unit testbenches (tb/run_regression.py)
regress:
	python tb/run_regression.py

# Official riscv-tests ISA suites on the research core and the FPGA SoC
compliance:
	python phase5/compliance/run_compliance.py

# riscv-formal on the FPGA SoC core (needs oss-cad-suite)
formal:
	python formal/riscv-formal/run_riscv_formal.py

verify: regress compliance formal

# Older names kept as aliases
phase5-all: regress
phase5-compliance-run: compliance
phase5-formal: formal

phase5-synthesis:
	@echo Phase 5 synthesis artifacts:
	@echo   docs/phase5_synthesis.md
	@echo   phase5/synthesis/README.md
	@echo   phase5/synthesis/core_constraints.tcl

phase5-clean:
	rm -f $(VVP) $(VCD) $(VVP_MULDIV) $(VVP_BRANCH) $(VVP_RV64) $(VVP_MMU) $(VVP_FP) $(VVP_VEC)
	rm -rf sim/regress phase5/compliance/build

# ============================================================
#  Phase 6 - Advanced Verification (Corner Cases)
# ============================================================
VVP_P6_ALU     := $(SIM_DIR)/p6_alu
VVP_P6_HAZARDS := $(SIM_DIR)/p6_hazards
VVP_P6_CONTROL := $(SIM_DIR)/p6_control

SRCS_P6_BASE := $(filter-out $(TB_DIR)/tb_cpu.sv,$(SRCS))

sim_p6_alu: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_P6_ALU) $(SRCS_P6_BASE) $(TB_DIR)/tb_phase6_alu.sv
	cd $(SIM_DIR) && vvp p6_alu

sim_p6_hazards: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_P6_HAZARDS) $(SRCS_P6_BASE) $(TB_DIR)/tb_phase6_hazards.sv
	cd $(SIM_DIR) && vvp p6_hazards

sim_p6_control: build-sim
	iverilog -g2012 -I$(RTL_DIR) -I$(TB_DIR) -o $(VVP_P6_CONTROL) $(SRCS_P6_BASE) $(TB_DIR)/tb_phase6_control.sv
	cd $(SIM_DIR) && vvp p6_control

phase6-all: sim_p6_alu sim_p6_hazards sim_p6_control
