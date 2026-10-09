/* ============================================================
 *  hello_asm.S  -  RV32 UART Hello World + Echo Test Firmware
 *
 *  Purpose: Minimal bare-metal UART test for the Arty S7 SoC.
 *    1. Set up machine trap vector (mtvec) explicitly.
 *    2. Flush any stale RX bytes left over from reset / BTN0.
 *    3. Print banner starting with CR+LF so it always appears
 *       on a fresh terminal line.
 *    4. Echo every received character back to the terminal.
 *
 *  UART memory map (base = 0x1000_0000):
 *    +0x00  [W]  TX Data   - write one byte to transmit
 *    +0x04  [R]  RX Data   - read one received byte
 *    +0x08  [R]  Status    - bit[0]=TX_READY, bit[1]=RX_VALID
 *
 *  PuTTY settings required:
 *    COM4, 115200 8N1, Flow = None
 *    Terminal > Local Echo       = Force Off
 *    Terminal > Local Line Edit  = Force Off
 *
 *  Register allocation (callee-saved across all helpers):
 *    s0 = UART base address (0x1000_0000)
 *    s2 = RX_VALID mask (0x2)
 * ============================================================ */

    .section .text.startup, "ax"
    .global _start

/* ------------------------------------------------------------ */
/*  Constants                                                    */
/* ------------------------------------------------------------ */
#define UART_BASE   0x10000000
#define UART_TX     0x00
#define UART_RX     0x04
#define UART_STAT   0x08
#define TX_READY    0x01
#define RX_VALID    0x02

/* ============================================================
 *  uart_putc_r: Send char already in a0.
 *  Uses: t0, t1.  s0 must already hold UART_BASE.
 * ============================================================ */
.macro uart_putc_r
    li    t1, TX_READY
99: lw    t0, UART_STAT(s0)
    and   t0, t0, t1
    beqz  t0, 99b
    sw    a0, UART_TX(s0)
.endm

/* ============================================================
 *  uart_putc_imm ch: Load literal char, then send.
 *  Uses: a0, t0, t1.
 * ============================================================ */
.macro uart_putc_imm ch
    li    a0, \ch
    uart_putc_r
.endm

/* ============================================================
 *  _start: CPU entry point after reset
 * ============================================================ */
_start:
    /* 1. Disable all interrupts */
    csrwi mie,     0
    csrwi mstatus, 0

    /* 2. Set saved registers */
    li    s0, UART_BASE
    li    s2, RX_VALID

    /* 3. Explicit mtvec setup -> _trap_handler */
    la    t0, _trap_handler
    csrw  mtvec, t0

    /* 4. Flush stale UART RX (from keys held during BTN0 press) */
flush_rx:
    lw    t0, UART_STAT(s0)
    andi  t0, t0, RX_VALID
    beqz  t0, flush_done
    lw    t0, UART_RX(s0)
    j     flush_rx
flush_done:

    /* 5. Print banner - starts with CR+LF for a fresh terminal line */
    uart_putc_imm '\r'
    uart_putc_imm '\n'
    uart_putc_imm 'H'
    uart_putc_imm 'e'
    uart_putc_imm 'l'
    uart_putc_imm 'l'
    uart_putc_imm 'o'
    uart_putc_imm ' '
    uart_putc_imm 'f'
    uart_putc_imm 'r'
    uart_putc_imm 'o'
    uart_putc_imm 'm'
    uart_putc_imm ' '
    uart_putc_imm 'R'
    uart_putc_imm 'I'
    uart_putc_imm 'S'
    uart_putc_imm 'C'
    uart_putc_imm '-'
    uart_putc_imm 'V'
    uart_putc_imm ' '
    uart_putc_imm 'S'
    uart_putc_imm 'o'
    uart_putc_imm 'C'
    uart_putc_imm '!'
    uart_putc_imm '\r'
    uart_putc_imm '\n'
    uart_putc_imm 'T'
    uart_putc_imm 'y'
    uart_putc_imm 'p'
    uart_putc_imm 'e'
    uart_putc_imm ' '
    uart_putc_imm 'a'
    uart_putc_imm 'n'
    uart_putc_imm 'y'
    uart_putc_imm 't'
    uart_putc_imm 'h'
    uart_putc_imm 'i'
    uart_putc_imm 'n'
    uart_putc_imm 'g'
    uart_putc_imm ':'
    uart_putc_imm ' '
    uart_putc_imm '\r'
    uart_putc_imm '\n'

/* ============================================================
 *  6. RX->TX echo loop (forever)
 *     s0 = UART base, s2 = RX_VALID
 * ============================================================ */
echo_loop:
wait_rx:
    lw    t0, UART_STAT(s0)
    and   t0, t0, s2
    beqz  t0, wait_rx

    lw    a0, UART_RX(s0)
    andi  a0, a0, 0xFF

    uart_putc_r

    /* If Enter key (\r) was typed, echo \n as well so PuTTY advances line */
    li    t0, '\r'
    bne   a0, t0, not_cr
    uart_putc_imm '\n'
not_cr:

    j     echo_loop

_halt:
    j     _halt

/* ============================================================
 *  Trap handler
 * ============================================================ */
    .section .text.trap, "ax"
    .global _trap_handler
    .align  4
_trap_handler:
    j     _halt