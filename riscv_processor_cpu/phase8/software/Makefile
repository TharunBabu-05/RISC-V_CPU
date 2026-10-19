# ============================================================
#  Makefile  —  RV32 SoC Firmware Build System
#
#  Builds the Snake game firmware for the custom RV32 CPU.
#
#  Prerequisites:
#    RISC-V GNU Toolchain installed, specifically:
#      riscv32-unknown-elf-gcc (or riscv64-unknown-elf-gcc)
#
#  Install toolchain (Windows — via WinGet or Chocolatey):
#    Option 1 (recommended): Download from
#      https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
#    Option 2: Use the toolchain bundled with SiFive Freedom Tools
#
#  Usage:
#    make          — Build the firmware (produces snake.hex)
#    make clean    — Remove build artifacts
#    make program  — Copy .hex into BRAM init file for synthesis
# ============================================================

# ---- Toolchain ----
CROSS   ?= C:/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf
CC       = $(CROSS)-gcc
OBJCOPY  = $(CROSS)-objcopy
OBJDUMP  = $(CROSS)-objdump
SIZE     = $(CROSS)-size

# ---- Compiler Flags ----
# -march=rv32i_zicsr_zifencei : RV32I + CSR + instruction-stream fence.
#                      Snake avoids M-extension ops for the FPGA boot test.
# -mabi=ilp32     : 32-bit integer, LP32 ABI (no floating-point ABI)
# -Os             : Optimize for code size (fits in 64KB BRAM)
# -ffreestanding  : No standard library (we write our own)
# -nostdlib       : No standard lib startup files
# -fno-builtin    : Don't use built-in functions (printf, memcpy etc.)
# -Wall           : Enable all warnings
CFLAGS  = -march=rv32i_zicsr_zifencei -mabi=ilp32 -Os -ffreestanding -nostdlib \
           -fno-builtin -Wall -I.

LDFLAGS = -T link.ld -nostdlib

# ---- Source Files ----
SRCS = startup.S uart.c snake.c

# ---- Output Files ----
TARGET  = snake
ELF     = $(TARGET).elf
BIN     = $(TARGET).bin
HEX     = $(TARGET).hex     # <- This is loaded into BRAM at synthesis
DUMP    = $(TARGET).dump    # Disassembly (useful for debugging)

# ---- Build Directory ----
BUILD   = build
OBJS    = $(addprefix $(BUILD)/, $(addsuffix .o, $(basename $(SRCS))))

# ============================================================
#  Default Target: Build firmware
# ============================================================
.PHONY: all clean program disasm size hello hello_program bootloader \
	bootloader_program app upload boot_test_app boot_test_flash flash_image qspi_mcs

all: $(BUILD)/$(HEX) $(BUILD)/$(DUMP)
	@echo ""
	@echo "=========================================="
	@echo "  Firmware built successfully!"
	@echo "  HEX file: $(BUILD)/$(HEX)"
	@echo "  Run 'make program' to install it as"
	@echo "  phase8/rtl/firmware.vmem."
	@echo "=========================================="

# ---- Link ELF ----
$(BUILD)/$(ELF): $(OBJS) link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS)
	$(SIZE) $@

# ---- Compile C files ----
$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# ---- Assemble startup ----
$(BUILD)/startup.o: startup.S | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# ---- Generate binary ----
$(BUILD)/$(BIN): $(BUILD)/$(ELF)
	$(OBJCOPY) -O binary $< $@

# ---- Generate Intel HEX (for $readmemh in BRAM) ----
$(BUILD)/$(HEX): $(BUILD)/$(BIN)
	$(OBJCOPY) -I binary -O ihex $< $@
	@echo "Generating Verilog hex file..."
	$(OBJCOPY) -O verilog --verilog-data-width=4 $(BUILD)/$(ELF) $(BUILD)/$(TARGET).vmem

# ---- Generate disassembly (for debugging) ----
$(BUILD)/$(DUMP): $(BUILD)/$(ELF)
	$(OBJDUMP) -d -M numeric,no-aliases $< > $@

# ---- Create build directory ----
$(BUILD):
	mkdir -p $(BUILD)

# ---- Copy HEX to synthesis directory ----
program: $(BUILD)/$(HEX)
	cp $(BUILD)/$(TARGET).vmem ../rtl/firmware.vmem
	@echo "Firmware copied to ../rtl/firmware.vmem"
	@echo "Re-run synthesis in Vivado to put it in the bitstream."
	@echo "Then re-run Vivado synthesis."

# ---- Print code size ----
size: $(BUILD)/$(ELF)
	$(SIZE) $<

# ---- Clean build artifacts ----
clean:
	rm -rf $(BUILD)

# ============================================================
#  Hello-World UART Test Firmware (hello_asm.S standalone build)
#  Usage:
#    make hello           — compile hello_asm.S → build/hello.vmem
#    make hello_program   — also copy to ../rtl/firmware.vmem
# ============================================================

HELLO_SRC = hello_asm.S
HELLO_ELF = $(BUILD)/hello.elf
HELLO_VMM = $(BUILD)/hello.vmem
HELLO_DMP = $(BUILD)/hello.dump

hello: $(HELLO_VMM) $(HELLO_DMP)
	@echo ""
	@echo "=========================================="
	@echo "  Hello-World firmware built: $(HELLO_VMM)"
	@echo "  Run  'make hello_program'  to install."
	@echo "=========================================="

$(HELLO_ELF): $(HELLO_SRC) link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(HELLO_SRC)
	$(SIZE) $@

$(HELLO_VMM): $(HELLO_ELF)
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

$(HELLO_DMP): $(HELLO_ELF)
	$(OBJDUMP) -d -M numeric,no-aliases $< > $@

hello_program: $(HELLO_VMM)
	cp $(HELLO_VMM) ../rtl/firmware.vmem
	@echo "Copied $(HELLO_VMM) -> ../rtl/firmware.vmem"
	@echo "Re-run Vivado synthesis to update BRAM init image."

# ============================================================
#  Resident QSPI Boot ROM, UART recovery, and relocated application
#
#  One-time FPGA image:
#    make bootloader_program
#
#  Volatile firmware updates (no synthesis):
#    make app
#    make upload PORT=COM4
#  Permanent QSPI image after Vivado generates the new bitstream:
#    make flash_image
#    make qspi_mcs
#  Add RUN=1 to upload and start a UART image immediately.
# ============================================================

BOOT_ELF = $(BUILD)/bootloader.elf
BOOT_BIN = $(BUILD)/bootloader.bin
BOOT_VMM = $(BUILD)/bootloader.vmem
BOOT_DMP = $(BUILD)/bootloader.dump

APP_ELF  = $(BUILD)/snake_app.elf
APP_BIN  = $(BUILD)/snake_app.bin
APP_DMP  = $(BUILD)/snake_app.dump
BOOT_TEST_BIN = $(BUILD)/boot_test_app.bin
BOOT_TEST_FLASH = $(BUILD)/boot_test_flash.bin
FLASH_BIN = $(BUILD)/snake_flash.bin
BITSTREAM ?= ../vivado/vivado_project/rv32_soc_arty_s7.runs/impl_1/soc_top.bit
FLASH_MCS ?= ../vivado/vivado_project/rv32_soc_with_app.mcs

$(BUILD)/bootloader.o: bootloader.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/qspi.o: qspi.c qspi.h soc.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ qspi.c

$(BOOT_ELF): $(BUILD)/startup.o $(BUILD)/uart.o $(BUILD)/qspi.o $(BUILD)/bootloader.o boot_link.ld
	$(CC) $(CFLAGS) -T boot_link.ld -nostdlib -o $@ \
		$(BUILD)/startup.o $(BUILD)/uart.o $(BUILD)/qspi.o $(BUILD)/bootloader.o
	$(SIZE) $@

$(BOOT_BIN): $(BOOT_ELF)
	$(OBJCOPY) -O binary $< $@

$(BOOT_VMM): $(BOOT_ELF)
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

$(BOOT_DMP): $(BOOT_ELF)
	$(OBJDUMP) -d -M numeric,no-aliases $< > $@

bootloader: $(BOOT_BIN) $(BOOT_VMM) $(BOOT_DMP)
	@echo "Resident bootloader built: $(BOOT_VMM)"

bootloader_program: bootloader
	cp $(BOOT_VMM) ../rtl/firmware.vmem
	@echo "Installed resident QSPI/UART Boot ROM in ../rtl/firmware.vmem"
	@echo "Rebuild the FPGA bitstream once, then use qspi_mcs for persistent firmware."

$(APP_ELF): $(OBJS) app_link.ld
	$(CC) $(CFLAGS) -T app_link.ld -nostdlib -o $@ $(OBJS)
	$(SIZE) $@

$(APP_BIN): $(APP_ELF)
	$(OBJCOPY) -O binary $< $@

$(APP_DMP): $(APP_ELF)
	$(OBJDUMP) -d -M numeric,no-aliases $< > $@

app: $(APP_BIN) $(APP_DMP)
	@echo "UART-loadable Snake image built: $(APP_BIN)"

$(FLASH_BIN): $(APP_BIN) pack_flash_image.ps1
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File pack_flash_image.ps1 \
		-InputFile $(APP_BIN) -OutputFile $(FLASH_BIN)

flash_image: $(FLASH_BIN)
	@echo "QSPI application image built: $(FLASH_BIN)"

qspi_mcs: flash_image
	"C:/Xilinx/Vivado/2020.2/bin/vivado.bat" -mode batch \
		-source ../vivado/generate_qspi_mcs.tcl \
		-tclargs $(BITSTREAM) $(FLASH_BIN) $(FLASH_MCS)
	@echo "Program $(FLASH_MCS) into configuration memory using Vivado Hardware Manager."

PORT ?= COM4
UPLOAD_DELAY ?= 2
UPLOAD_RUN = $(if $(RUN),-Run,)
upload: app
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File uart_upload.ps1 \
		-Port $(PORT) -File $(APP_BIN) -InterByteDelayMs $(UPLOAD_DELAY) $(UPLOAD_RUN)

$(BUILD)/boot_test_app.elf: ../tb/boot_test_app.S app_link.ld | $(BUILD)
	$(CC) $(CFLAGS) -T app_link.ld -nostdlib -o $@ $<

$(BOOT_TEST_BIN): $(BUILD)/boot_test_app.elf
	$(OBJCOPY) -O binary $< $@

boot_test_app: $(BOOT_TEST_BIN)

$(BOOT_TEST_FLASH): $(BOOT_TEST_BIN) pack_flash_image.ps1
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File pack_flash_image.ps1 \
		-InputFile $(BOOT_TEST_BIN) -OutputFile $(BOOT_TEST_FLASH)

boot_test_flash: $(BOOT_TEST_FLASH)

# Isolated DDR diagnostic image; deliberately never installs firmware.vmem.
.PHONY: ddr_test ddr_project
DDR_CFLAGS = -march=rv32im_zicsr_zifencei -mabi=ilp32 -Os -ffreestanding \
	-nostdlib -fno-builtin -Wall -Wextra -I.
$(BUILD)/ddr_test.elf: startup.S uart.c ddr_test.c ddr_probe.S soc.h uart.h link.ld | $(BUILD)
	$(CC) $(DDR_CFLAGS) -T link.ld -o $@ startup.S uart.c ddr_test.c ddr_probe.S
	$(SIZE) $@
$(BUILD)/ddr_test.vmem: $(BUILD)/ddr_test.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
ddr_test: $(BUILD)/ddr_test.vmem
	@echo "DDR diagnostic built separately: $(BUILD)/ddr_test.vmem"

ddr_project: ddr_test
	"C:/Xilinx/Vivado/2020.2/bin/vivado.bat" -mode batch \
		-source ../vivado/create_ddr_project.tcl
	@echo "Open ../vivado/ddr_project/arty_s7_ddr_bringup/rv32_soc_arty_s7.xpr in Vivado."

# Isolated DDR loader and executable. Does not change Snake or DDR diagnostic.
.PHONY: ddr_loader ddr_app_test ddr_upload ddr_loader_project
$(BUILD)/ddr_loader.elf: startup.S uart.c ddr_loader.c boot_link.ld | $(BUILD)
	$(CC) $(DDR_CFLAGS) -T boot_link.ld -o $@ startup.S uart.c ddr_loader.c
	$(SIZE) $@
$(BUILD)/ddr_loader.vmem: $(BUILD)/ddr_loader.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
ddr_loader: $(BUILD)/ddr_loader.vmem
	@echo "Separate DDR loader built: $(BUILD)/ddr_loader.vmem"

$(BUILD)/ddr_app_test.elf: startup.S uart.c ddr_app_test.c ddr_app_link.ld | $(BUILD)
	$(CC) $(DDR_CFLAGS) -T ddr_app_link.ld -o $@ startup.S uart.c ddr_app_test.c
	$(SIZE) $@
$(BUILD)/ddr_app_test.bin: $(BUILD)/ddr_app_test.elf
	$(OBJCOPY) -O binary $< $@
ddr_app_test: $(BUILD)/ddr_app_test.bin
	@echo "DDR-linked test application built: $(BUILD)/ddr_app_test.bin"

ddr_upload: ddr_app_test
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ddr_upload.ps1 \
		-Port $(PORT) -File $(BUILD)/ddr_app_test.bin -InterByteDelayMs $(UPLOAD_DELAY) $(UPLOAD_RUN)

ddr_loader_project: ddr_loader
	"C:/Xilinx/Vivado/2020.2/bin/vivado.bat" -mode batch \
		-source ../vivado/create_ddr_project.tcl \
		-tclargs ../vivado/ddr_project/arty_s7_ddr_loader $(BUILD)/ddr_loader.vmem
	@echo "Open ../vivado/ddr_project/arty_s7_ddr_loader/rv32_soc_arty_s7.xpr in Vivado."
