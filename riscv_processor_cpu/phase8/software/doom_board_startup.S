    .section .text.startup, "ax"
    .global _start
_start:
    csrw mie, zero
    csrw mstatus, zero
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, _stack_top
    la t0, _trap_handler
    csrw mtvec, t0
    la a0, _bss_start
    la a1, _bss_end
1:
    bge a0, a1, 2f
    sw zero, 0(a0)
    addi a0, a0, 4
    j 1b
2:
    call main
3:
    j 3b

    .section .text.trap, "ax"
    .align 4
_trap_handler:
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call doom_board_trap
4:
    j 4b
