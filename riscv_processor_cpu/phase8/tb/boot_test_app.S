/* Minimal application used by tb_bootloader.sv.
 * It is uploaded to 0x4000 and prints APP:OK when control reaches it.
 */

    .section .text.startup, "ax"
    .global _start

.macro putc value
    li      a0, \value
1:  lw      t0, 8(s0)
    andi    t0, t0, 1
    beqz    t0, 1b
    sw      a0, 0(s0)
.endm

_start:
    csrwi   mie, 0
    csrwi   mstatus, 0
    li      s0, 0x10000000

    putc    'A'
    putc    'P'
    putc    'P'
    putc    ':'
    putc    'O'
    putc    'K'
    putc    '\r'
    putc    '\n'

1:  j       1b
