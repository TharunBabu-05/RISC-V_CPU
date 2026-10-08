/* ============================================================
 *  hello_asm.S  —  Pure-assembly UART Hello + Echo
 *
 *  This firmware requires NO stack, NO C runtime, NO heap.
 *  It is the simplest possible program to prove UART works:
 *    1. Spin-wait until UART TX is ready  (UART_STATUS bit 0)
 *    2. Write one character at a time     (UART_TX offset 0x00)
 *    3. After banner, loop echoing RX→TX  (UART_STATUS bit 1)
 *
 *  Memory Map (must match soc_top.sv and link.ld):
 *    0x0000_0000 : start of BRAM (this code runs here)
 *    0x1000_0000 : UART_TX   (write-only, offset +0x00)
 *    0x1000_0004 : UART_RX   (read-only,  offset +0x04)
 *    0x1000_0008 : UART_STAT (read-only,  bit0=TX_READY, bit1=RX_VALID)
 * ============================================================ */

    .section .text.startup, "ax"
    .global _start
    .global _halt

/* ---- UART register base ---- */
#define UART_BASE    0x10000000
#define UART_TX_OFF  0x00
#define UART_RX_OFF  0x04
#define UART_ST_OFF  0x08
#define TX_READY     0x01
#define RX_VALID     0x02

/* ---- Macro: send one char in register a0, clobbers t0, t1, t2 ---- */
.macro putc  reg
    li    t1, UART_BASE
    li    t2, TX_READY
1:  lw    t0, UART_ST_OFF(t1)     /* read UART_STATUS */
    and   t0, t0, t2
    beqz  t0, 1b                  /* spin while TX busy */
    sw    \reg, UART_TX_OFF(t1)   /* write byte */
.endm

_start:
    /* --- Disable all interrupts (CSRs) --- */
    csrwi mie,     0
    csrwi mstatus, 0

    /* --- Load UART base into s0 (saved across the banner loop) --- */
    li    s0, UART_BASE

    /* --- Print banner string character by character --- */
    /* "Hello from RISC-V SoC!\r\n" */
    li    a0, 'H' ; putc a0
    li    a0, 'e' ; putc a0
    li    a0, 'l' ; putc a0
    li    a0, 'l' ; putc a0
    li    a0, 'o' ; putc a0
    li    a0, ' ' ; putc a0
    li    a0, 'f' ; putc a0
    li    a0, 'r' ; putc a0
    li    a0, 'o' ; putc a0
    li    a0, 'm' ; putc a0
    li    a0, ' ' ; putc a0
    li    a0, 'R' ; putc a0
    li    a0, 'I' ; putc a0
    li    a0, 'S' ; putc a0
    li    a0, 'C' ; putc a0
    li    a0, '-' ; putc a0
    li    a0, 'V' ; putc a0
    li    a0, ' ' ; putc a0
    li    a0, 'S' ; putc a0
    li    a0, 'o' ; putc a0
    li    a0, 'C' ; putc a0
    li    a0, '!' ; putc a0
    li    a0, '\r'; putc a0
    li    a0, '\n'; putc a0

    li    a0, 'T' ; putc a0
    li    a0, 'y' ; putc a0
    li    a0, 'p' ; putc a0
    li    a0, 'e' ; putc a0
    li    a0, ' ' ; putc a0
    li    a0, 'a' ; putc a0
    li    a0, 'n' ; putc a0
    li    a0, 'y' ; putc a0
    li    a0, 't' ; putc a0
    li    a0, 'h' ; putc a0
    li    a0, 'i' ; putc a0
    li    a0, 'n' ; putc a0
    li    a0, 'g' ; putc a0
    li    a0, ':' ; putc a0
    li    a0, ' ' ; putc a0
    li    a0, '\r'; putc a0
    li    a0, '\n'; putc a0

    /* --- RX→TX echo loop (forever) --- */
    li    t3, RX_VALID
echo_loop:
    lw    t0, UART_ST_OFF(s0)     /* read UART_STATUS */
    and   t0, t0, t3
    beqz  t0, echo_loop           /* loop until a byte arrives */

    lw    a0, UART_RX_OFF(s0)     /* read received byte */
    andi  a0, a0, 0xFF            /* mask to 8 bits */

    /* Echo it back */
    li    t2, TX_READY
tx_wait:
    lw    t0, UART_ST_OFF(s0)
    and   t0, t0, t2
    beqz  t0, tx_wait
    sw    a0, UART_TX_OFF(s0)     /* send the byte */

    j     echo_loop               /* wait for next byte */

_halt:
    j     _halt                   /* should never reach here */

/* ---- Minimal trap handler: just halt ---- */
    .section .text.trap, "ax"
    .global _trap_handler
    .align 4
_trap_handler:
    j     _halt
