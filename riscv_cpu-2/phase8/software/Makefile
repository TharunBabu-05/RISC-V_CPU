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
# Try riscv32-unknown-elf first; fall back to riscv64-unknown-elf
CROSS   ?= riscv32-unknown-elf
CC       = $(CROSS)-gcc
OBJCOPY  = $(CROSS)-objcopy
OBJDUMP  = $(CROSS)-objdump
SIZE     = $(CROSS)-size

# ---- Compiler Flags ----
# -march=rv32i    : Target RV32I base ISA (our CPU ISA)
# -mabi=ilp32     : 32-bit integer, LP32 ABI (no floating-point ABI)
# -Os             : Optimize for code size (fits in 64KB BRAM)
# -ffreestanding  : No standard library (we write our own)
# -nostdlib       : No standard lib startup files
# -fno-builtin    : Don't use built-in functions (printf, memcpy etc.)
# -Wall           : Enable all warnings
CFLAGS  = -march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib \
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
.PHONY: all clean program disasm size

all: $(BUILD)/$(HEX) $(BUILD)/$(DUMP)
	@echo ""
	@echo "=========================================="
	@echo "  Firmware built successfully!"
	@echo "  HEX file: $(BUILD)/$(HEX)"
	@echo "  Copy this file to phase8/rtl/ and update"
	@echo "  bram.sv INIT_FILE parameter."
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
	@echo "Now update bram.sv: set INIT_FILE = \"firmware.vmem\""
	@echo "Then re-run Vivado synthesis."

# ---- Print code size ----
size: $(BUILD)/$(ELF)
	$(SIZE) $<

# ---- Clean build artifacts ----
clean:
	rm -rf $(BUILD)
