/* Bare-metal helpers for the Phase 8 single-channel DMA controller. */
#ifndef DMA_H
#define DMA_H

#include <stddef.h>
#include <stdint.h>
#include "soc.h"

static inline void dma_start(uintptr_t source, uintptr_t destination,
                             uint32_t length, uint32_t control)
{
    while (DMA_STATUS & DMA_STATUS_BUSY)
        ;

    /* Clear sticky completion, error, and interrupt state. */
    DMA_STATUS = DMA_STATUS_DONE | DMA_STATUS_ERROR |
                 DMA_STATUS_IRQ_PENDING;
    DMA_SRC_ADDR = (uint32_t)source;
    DMA_DST_ADDR = (uint32_t)destination;
    DMA_LENGTH = length;
    __asm__ volatile ("fence rw, rw" : : : "memory");
    DMA_CONTROL = control | DMA_CONTROL_START;
}

static inline int dma_wait(void)
{
    uint32_t status;

    do {
        status = DMA_STATUS;
    } while (status & DMA_STATUS_BUSY);

    __asm__ volatile ("fence rw, rw" : : : "memory");
    return (status & DMA_STATUS_ERROR) ? -1 : 0;
}

static inline int dma_copy(void *destination, const void *source,
                           uint32_t length)
{
    uintptr_t src = (uintptr_t)source;
    uintptr_t dst = (uintptr_t)destination;
    uint32_t width = DMA_CONTROL_WIDTH_BYTE;

    if (((src | dst | length) & 3U) == 0U)
        width = DMA_CONTROL_WIDTH_WORD;
    else if (((src | dst | length) & 1U) == 0U)
        width = DMA_CONTROL_WIDTH_HALF;

    dma_start(src, dst, length, DMA_CONTROL_SRC_INC |
              DMA_CONTROL_DST_INC | width);
    return dma_wait();
}

static inline void dma_uart_transmit(const void *source, uint32_t length,
                                     int interrupt_enable)
{
    uint32_t control = DMA_CONTROL_SRC_INC | DMA_CONTROL_WIDTH_BYTE;

    if (interrupt_enable)
        control |= DMA_CONTROL_IRQ_ENABLE;
    dma_start((uintptr_t)source, UART_BASE, length, control);
}

static inline void dma_uart_receive(void *destination, uint32_t length,
                                    int interrupt_enable)
{
    uint32_t control = DMA_CONTROL_DST_INC | DMA_CONTROL_WIDTH_BYTE;

    if (interrupt_enable)
        control |= DMA_CONTROL_IRQ_ENABLE;
    dma_start(UART_BASE + 0x04U, (uintptr_t)destination, length, control);
}

static inline void dma_abort(void)
{
    DMA_CONTROL = DMA_CONTROL_ABORT;
}

#endif /* DMA_H */
