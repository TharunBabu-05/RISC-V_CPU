/* ============================================================
 *  soc.h  —  SoC Memory-Mapped Register Definitions
 *
 *  Central header for all hardware register addresses.
 *  Include this in any C firmware file.
 * ============================================================ */

#ifndef SOC_H
#define SOC_H

#include <stdint.h>

/* ---- UART Base Address ---- */
#define UART_BASE    0x10000000UL

/* ---- UART Register Offsets ---- */
#define UART_TX      (*(volatile uint32_t *)(UART_BASE + 0x00))  /* W: TX byte */
#define UART_RX      (*(volatile uint32_t *)(UART_BASE + 0x04))  /* R: RX byte */
#define UART_STATUS  (*(volatile uint32_t *)(UART_BASE + 0x08))  /* R: status  */

/* ---- UART Status Bits ---- */
#define UART_TX_READY   (1U << 0)   /* 1 = transmitter idle, safe to write  */
#define UART_RX_VALID   (1U << 1)   /* 1 = received byte waiting to be read */

/* ---- Data BRAM Base (optional heap) ---- */
#define DMEM_BASE    0x20000000UL

#endif /* SOC_H */
