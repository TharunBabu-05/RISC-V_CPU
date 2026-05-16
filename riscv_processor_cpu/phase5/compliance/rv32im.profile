ISA=rv32im
XLEN=32
EXTENSIONS=IM
TEST_SUITE=riscv-tests
SIGNATURE_DIR=phase5/compliance/signature/rv32im
COMMAND_TEMPLATE=make -C {suite_root} ISA={isa} XLEN={xlen} EXTENSIONS={extensions} SIGNATURE_DIR={signature_dir}