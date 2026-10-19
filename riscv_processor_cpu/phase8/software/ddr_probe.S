    .section .text.ddr_probe,"ax"
    .balign 4
    .global ddr_probe_start, ddr_probe_end
ddr_probe_start:
    mv t0, a0
    li a0, 0
1:  add a0, a0, t0
    addi t0, t0, -1
    bnez t0, 1b
    ret
ddr_probe_end:

    .section .text.ddr_trap,"ax"
    .balign 4
    .global ddr_trap
ddr_trap:
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    tail ddr_trap_report
