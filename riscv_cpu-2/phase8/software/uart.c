/* ============================================================
 *  uart.c  —  UART Driver Implementation (Polled Mode)
 * ============================================================ */

#include "uart.h"
#include "soc.h"

/* No hardware init needed for polled UART */
void uart_init(void) { }

/* ---- Send one byte (blocks until TX FIFO ready) ---- */
void uart_putc(char c) {
    while (!(UART_STATUS & UART_TX_READY));
    UART_TX = (uint32_t)(uint8_t)c;
}

/* ---- Receive one byte (blocks until data arrives) ---- */
char uart_getc(void) {
    while (!(UART_STATUS & UART_RX_VALID));
    return (char)(UART_RX & 0xFF);
}

/* ---- Non-blocking check: is a byte waiting? ---- */
int uart_kbhit(void) {
    return (UART_STATUS & UART_RX_VALID) ? 1 : 0;
}

/* ---- Send a null-terminated string ---- */
void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

/* ---- Newline: CR+LF for serial terminal compatibility ---- */
void uart_newline(void) {
    uart_putc('\r');
    uart_putc('\n');
}

/* ---- Print a signed integer in decimal ---- */
void uart_print_int(int n) {
    char buf[12];
    int  i = 0;
    int  neg = 0;

    if (n == 0) { uart_putc('0'); return; }

    if (n < 0) { neg = 1; n = -n; }

    while (n > 0) {
        buf[i++] = '0' + (n % 10);
        n /= 10;
    }
    if (neg) buf[i++] = '-';

    /* Reverse and print */
    while (i-- > 0) uart_putc(buf[i]);
}

/* ---- ANSI escape: clear screen and move cursor to (1,1) ---- */
void uart_clear_screen(void) {
    uart_puts("\033[2J\033[H");
}

/* ---- ANSI escape: move cursor to row, col (1-indexed) ---- */
void uart_move_cursor(int row, int col) {
    uart_puts("\033[");
    uart_print_int(row);
    uart_putc(';');
    uart_print_int(col);
    uart_putc('H');
}

/* ---- ANSI escape: hide cursor (cleaner game display) ---- */
void uart_hide_cursor(void) {
    uart_puts("\033[?25l");
}

/* ---- ANSI escape: show cursor ---- */
void uart_show_cursor(void) {
    uart_puts("\033[?25h");
}
