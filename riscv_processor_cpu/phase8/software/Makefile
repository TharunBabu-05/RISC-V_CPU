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
	bootloader_program app upload boot_test_app

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
#  Resident UART bootloader and relocated application
#
#  One-time FPGA image:
#    make bootloader_program
#
#  Subsequent firmware updates (no synthesis):
#    make app
#    make upload PORT=COM4
#  Then open PuTTY and press G. Add RUN=1 to upload and start immediately.
# ============================================================

BOOT_ELF = $(BUILD)/bootloader.elf
BOOT_BIN = $(BUILD)/bootloader.bin
BOOT_VMM = $(BUILD)/bootloader.vmem
BOOT_DMP = $(BUILD)/bootloader.dump

APP_ELF  = $(BUILD)/snake_app.elf
APP_BIN  = $(BUILD)/snake_app.bin
APP_DMP  = $(BUILD)/snake_app.dump
BOOT_TEST_BIN = $(BUILD)/boot_test_app.bin

$(BUILD)/bootloader.o: bootloader.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BOOT_ELF): $(BUILD)/startup.o $(BUILD)/uart.o $(BUILD)/bootloader.o boot_link.ld
	$(CC) $(CFLAGS) -T boot_link.ld -nostdlib -o $@ \
		$(BUILD)/startup.o $(BUILD)/uart.o $(BUILD)/bootloader.o
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
	@echo "Installed resident bootloader in ../rtl/firmware.vmem"
	@echo "Rebuild the FPGA bitstream once. Future application uploads use UART."

$(APP_ELF): $(OBJS) app_link.ld
	$(CC) $(CFLAGS) -T app_link.ld -nostdlib -o $@ $(OBJS)
	$(SIZE) $@

$(APP_BIN): $(APP_ELF)
	$(OBJCOPY) -O binary $< $@

$(APP_DMP): $(APP_ELF)
	$(OBJDUMP) -d -M numeric,no-aliases $< > $@

app: $(APP_BIN) $(APP_DMP)
	@echo "UART-loadable Snake image built: $(APP_BIN)"

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
