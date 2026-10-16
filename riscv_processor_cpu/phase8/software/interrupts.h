/* Bare-metal helpers for the single-hart CLINT and PLIC. */
#ifndef INTERRUPTS_H
#define INTERRUPTS_H

#include <stdint.h>
#include "soc.h"

static inline void machine_trap_vector_set(void (*handler)(void))
{
    uintptr_t address = (uintptr_t)handler;
    __asm__ volatile ("csrw mtvec, %0" : : "r"(address) : "memory");
}

static inline void machine_interrupts_enable(uint32_t mask)
{
    __asm__ volatile ("csrs mie, %0" : : "r"(mask) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" : : : "memory");
}

static inline void machine_interrupts_disable(void)
{
    __asm__ volatile ("csrci mstatus, 8" : : : "memory");
}

static inline uint64_t clint_mtime_read(void)
{
    uint32_t hi_before;
    uint32_t lo;
    uint32_t hi_after;

    do {
        hi_before = CLINT_MTIME_HI;
        lo = CLINT_MTIME_LO;
        hi_after = CLINT_MTIME_HI;
    } while (hi_before != hi_after);

    return ((uint64_t)hi_after << 32) | lo;
}

static inline void clint_mtimecmp_write(uint64_t deadline)
{
    /* Prevent a transient match while updating a 64-bit register on RV32. */
    CLINT_MTIMECMP_HI = UINT32_MAX;
    CLINT_MTIMECMP_LO = (uint32_t)deadline;
    CLINT_MTIMECMP_HI = (uint32_t)(deadline >> 32);
}

static inline void clint_software_interrupt_set(int pending)
{
    CLINT_MSIP = pending ? 1U : 0U;
}

static inline void plic_source_enable(uint32_t source, uint32_t priority)
{
    if (source >= 1U && source <= PLIC_IRQ_MAX) {
        PLIC_PRIORITY(source) = priority & 7U;
        PLIC_ENABLE |= 1U << source;
    }
}

static inline void plic_threshold_set(uint32_t threshold)
{
    PLIC_THRESHOLD = threshold & 7U;
}

static inline uint32_t plic_claim(void)
{
    return PLIC_CLAIM_COMPLETE;
}

static inline void plic_complete(uint32_t source)
{
    PLIC_CLAIM_COMPLETE = source;
}

#endif /* INTERRUPTS_H */
