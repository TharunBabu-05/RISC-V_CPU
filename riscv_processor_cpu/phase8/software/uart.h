/* ============================================================
 *  uart.h  —  UART Driver API (Polled Mode)
 *
 *  Simple blocking UART driver for the SoC UART peripheral.
 *  Uses polling (no interrupts) — sufficient for a game.
 * ============================================================ */

#ifndef UART_H
#define UART_H

#include <stdint.h>

/* Initialize UART (no-op for polled mode, but defined for clarity) */
void uart_init(void);

/* Send a single character (blocks until TX ready) */
void uart_putc(char c);

/* Receive a single character (blocks until data available) */
char uart_getc(void);

/* Non-blocking: returns 1 if a character is waiting to be read */
int  uart_kbhit(void);

/* Send a null-terminated string */
void uart_puts(const char *s);

/* Send a newline (CR+LF for terminal compatibility) */
void uart_newline(void);

/* Print an integer (decimal) */
void uart_print_int(int n);

/* Clear the terminal screen using ANSI escape codes */
void uart_clear_screen(void);

/* Move cursor to row, col (1-indexed) using ANSI escape codes */
void uart_move_cursor(int row, int col);

/* Hide/show cursor using ANSI escape codes */
void uart_hide_cursor(void);
void uart_show_cursor(void);

#endif /* UART_H */
