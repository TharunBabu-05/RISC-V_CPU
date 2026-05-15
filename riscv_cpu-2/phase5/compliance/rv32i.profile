ISA=rv32i
XLEN=32
EXTENSIONS=I
TEST_SUITE=riscv-tests
SIGNATURE_DIR=phase5/compliance/signature/rv32i
COMMAND_TEMPLATE=make -C {suite_root} ISA={isa} XLEN={xlen} EXTENSIONS={extensions} SIGNATURE_DIR={signature_dir}