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
#define UART_RX_OVERFLOW (1U << 2)  /* 1 = at least one RX byte was dropped */

/* ---- Core-Local Interruptor (CLINT) ---- */
#define CLINT_BASE          0x02000000UL
#define CLINT_MSIP          (*(volatile uint32_t *)(CLINT_BASE + 0x0000))
#define CLINT_MTIMECMP_LO   (*(volatile uint32_t *)(CLINT_BASE + 0x4000))
#define CLINT_MTIMECMP_HI   (*(volatile uint32_t *)(CLINT_BASE + 0x4004))
#define CLINT_MTIME_LO      (*(volatile uint32_t *)(CLINT_BASE + 0xBFF8))
#define CLINT_MTIME_HI      (*(volatile uint32_t *)(CLINT_BASE + 0xBFFC))

/* ---- Platform-Level Interrupt Controller (PLIC) ---- */
#define PLIC_BASE           0x0C000000UL
#define PLIC_PRIORITY(id)   (*(volatile uint32_t *)(PLIC_BASE + 4U * (id)))
#define PLIC_PENDING        (*(volatile uint32_t *)(PLIC_BASE + 0x001000))
#define PLIC_ENABLE         (*(volatile uint32_t *)(PLIC_BASE + 0x002000))
#define PLIC_THRESHOLD      (*(volatile uint32_t *)(PLIC_BASE + 0x200000))
#define PLIC_CLAIM_COMPLETE (*(volatile uint32_t *)(PLIC_BASE + 0x200004))

#define PLIC_IRQ_UART       1U
#define PLIC_IRQ_GPIO       2U
#define PLIC_IRQ_SPI        3U
#define PLIC_IRQ_EXTERNAL   4U
#define PLIC_IRQ_DMA        5U
#define PLIC_IRQ_MAX        PLIC_IRQ_DMA

/* Machine interrupt-enable/pending bit positions. */
#define MIP_MSIP            (1U << 3)
#define MIP_MTIP            (1U << 7)
#define MIP_MEIP            (1U << 11)

/* ---- Read-only QSPI boot controller ---- */
#define QSPI_BASE           0x10001000UL
#define QSPI_ADDRESS        (*(volatile uint32_t *)(QSPI_BASE + 0x00))
#define QSPI_DATA           (*(volatile uint32_t *)(QSPI_BASE + 0x04))
#define QSPI_CONTROL        (*(volatile uint32_t *)(QSPI_BASE + 0x08))
#define QSPI_STATUS         QSPI_CONTROL
#define QSPI_ID             (*(volatile uint32_t *)(QSPI_BASE + 0x0C))

#define QSPI_CONTROL_START  (1U << 0)
#define QSPI_STATUS_BUSY    (1U << 0)
#define QSPI_STATUS_DONE    (1U << 1)

/* ---- Single-channel DMA controller ---- */
#define DMA_BASE            0x10002000UL
#define DMA_SRC_ADDR        (*(volatile uint32_t *)(DMA_BASE + 0x00))
#define DMA_DST_ADDR        (*(volatile uint32_t *)(DMA_BASE + 0x04))
#define DMA_LENGTH          (*(volatile uint32_t *)(DMA_BASE + 0x08))
#define DMA_CONTROL         (*(volatile uint32_t *)(DMA_BASE + 0x0C))
#define DMA_STATUS          (*(volatile uint32_t *)(DMA_BASE + 0x10))
#define DMA_TRANSFERRED     (*(volatile uint32_t *)(DMA_BASE + 0x14))
#define DMA_ID              (*(volatile uint32_t *)(DMA_BASE + 0x18))
#define DMA_REMAINING       (*(volatile uint32_t *)(DMA_BASE + 0x1C))

#define DMA_CONTROL_START       (1U << 0)
#define DMA_CONTROL_SRC_INC     (1U << 1)
#define DMA_CONTROL_DST_INC     (1U << 2)
#define DMA_CONTROL_WIDTH_BYTE  (0U << 3)
#define DMA_CONTROL_WIDTH_HALF  (1U << 3)
#define DMA_CONTROL_WIDTH_WORD  (2U << 3)
#define DMA_CONTROL_IRQ_ENABLE  (1U << 5)
#define DMA_CONTROL_ABORT       (1U << 6)

#define DMA_STATUS_BUSY         (1U << 0)
#define DMA_STATUS_DONE         (1U << 1)
#define DMA_STATUS_ERROR        (1U << 2)
#define DMA_STATUS_IRQ_PENDING  (1U << 3)
#define DMA_STATUS_ERROR_SHIFT  8U

#define DMA_ERROR_BAD_WIDTH     1U
#define DMA_ERROR_SELF_ACCESS   2U
#define DMA_ERROR_BUS           3U
#define DMA_ERROR_ABORTED       4U

#endif /* SOC_H */
