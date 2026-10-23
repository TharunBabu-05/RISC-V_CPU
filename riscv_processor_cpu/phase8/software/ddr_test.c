/* TCM-resident, destructive DDR bring-up. No changes to the Snake boot image. */
#include <stdint.h>
#include "soc.h"
#include "uart.h"

#define MEMINFO ((volatile uint32_t *)0x10003000u)
#define DDR ((volatile uint32_t *)0x80000000u)
#ifndef DDR_TEST_WORDS
#define DDR_TEST_WORDS 4096u
#endif
#define TIMEOUT_TICKS 125000000u
extern const uint32_t ddr_probe_start[], ddr_probe_end[];
extern void ddr_trap(void);
static uint32_t dma_source[64], dma_dest[64];

static void hex(uint32_t x) {
    static const char digits[] = "0123456789ABCDEF";
    for (int n = 28; n >= 0; n -= 4) uart_putc(digits[(x >> n) & 15]);
}

static void fail(uint32_t address, uint32_t expected, uint32_t actual) {
    uart_puts("DDR:FAIL addr="); hex(address);
    uart_puts(" expected="); hex(expected);
    uart_puts(" actual="); hex(actual); uart_newline();
    for (;;) { }
}

void ddr_trap_report(uint32_t cause, uint32_t pc, uint32_t value) {
    uart_puts("DDR:TRAP cause="); hex(cause);
    uart_puts(" pc="); hex(pc); uart_puts(" value="); hex(value); uart_newline();
    for (;;) { }
}

static void check(volatile uint32_t *p, uint32_t expected) {
    uint32_t actual = *p;
    if (actual != expected) fail((uint32_t)p, expected, actual);
}

static uint32_t pattern(uint32_t x) {
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return x;
}

static void dma_copy(uint32_t src, uint32_t dst) {
    DMA_STATUS = DMA_STATUS_DONE | DMA_STATUS_ERROR | DMA_STATUS_IRQ_PENDING;
    DMA_SRC_ADDR = src; DMA_DST_ADDR = dst; DMA_LENGTH = sizeof(dma_source);
    __asm__ volatile ("fence rw,rw" ::: "memory");
    DMA_CONTROL = DMA_CONTROL_START | DMA_CONTROL_SRC_INC |
                  DMA_CONTROL_DST_INC | DMA_CONTROL_WIDTH_WORD;
    uint32_t start = CLINT_MTIME_LO;
    while (DMA_STATUS & DMA_STATUS_BUSY)
        if ((uint32_t)(CLINT_MTIME_LO - start) > TIMEOUT_TICKS)
            fail(DMA_BASE, DMA_STATUS_DONE, DMA_STATUS);
    if ((DMA_STATUS & (DMA_STATUS_DONE | DMA_STATUS_ERROR)) != DMA_STATUS_DONE)
        fail(DMA_BASE, DMA_STATUS_DONE, DMA_STATUS);
    __asm__ volatile ("fence rw,rw" ::: "memory");
}

static void run_tests(void) {
    const uint32_t size = MEMINFO[3];
    volatile uint32_t *last = (volatile uint32_t *)(0x80000000u + size - 4);
    for (unsigned bit = 0; bit < 32; ++bit) {
        DDR[0] = 1u << bit; check(DDR, 1u << bit);
        DDR[0] = ~(1u << bit); check(DDR, ~(1u << bit));
    }
    DDR[0] = 0x12345678; *last = 0x87654321;
    check(DDR, 0x12345678); check(last, 0x87654321);
    // Independent locations expose aliased address lines across all 256 MiB.
    for (uint32_t off = 4; off < size; off <<= 1)
        DDR[off >> 2] = off ^ 0x5A5A1234u;
    for (uint32_t off = 4; off < size; off <<= 1)
        check(DDR + (off >> 2), off ^ 0x5A5A1234u);
    uart_puts("DDR:ADDRESS PASS\r\n");

    volatile uint8_t *bytes = (volatile uint8_t *)(DDR + 128);
    for (unsigned i = 0; i < 32; ++i) bytes[i] = 0;
    for (unsigned i = 0; i < 32; ++i) bytes[i] = (uint8_t)(i + 0x40);
    for (unsigned i = 0; i < 32; ++i)
        if (bytes[i] != i + 0x40) fail((uint32_t)(bytes + i), i + 0x40, bytes[i]);
    for (unsigned i = 0; i < 16; ++i) {
        volatile uint16_t *p = (volatile uint16_t *)(bytes + 2*i);
        *p = (uint16_t)(0xCA00 + i);
        if (*p != 0xCA00 + i) fail((uint32_t)p, 0xCA00 + i, *p);
    }
    uart_puts("DDR:LANES PASS\r\n");
    uint32_t seed = 0x31415926;
    for (unsigned i = 0; i < DDR_TEST_WORDS; ++i) DDR[i] = seed = pattern(seed);
    seed = 0x31415926;
    for (unsigned i = 0; i < DDR_TEST_WORDS; ++i) check(DDR + i, seed = pattern(seed));
    for (unsigned i = 0; i < DDR_TEST_WORDS; ++i) DDR[i] = ~DDR[i];
    seed = 0x31415926;
    for (unsigned i = 0; i < DDR_TEST_WORDS; ++i) check(DDR + i, ~(seed = pattern(seed)));
    uart_puts("DDR:PATTERN PASS\r\n");

    for (unsigned i = 0; i < 64; ++i) { dma_source[i] = i ^ 0xC001D00D; dma_dest[i] = 0; }
    // Warm destination lines before DMA replaces them. CPU reads must see
    // DMA writes without a software flush at the shared DDR cache port.
    volatile uint32_t *dma_ddr = (volatile uint32_t *)0x80004000u;
    for (unsigned i = 0; i < 64; ++i) dma_ddr[i] = 0xA5A5A5A5;
    for (unsigned i = 0; i < 64; ++i) check(dma_ddr + i, 0xA5A5A5A5);
    dma_copy((uint32_t)dma_source, 0x80004000);
    for (unsigned i = 0; i < 64; ++i) check(dma_ddr + i, dma_source[i]);
    // Reverse direction: CPU stores into warm lines followed by DMA reads.
    for (unsigned i = 0; i < 64; ++i) {
        dma_source[i] ^= 0x12345678;
        dma_ddr[i] = dma_source[i];
    }
    dma_copy(0x80004000, (uint32_t)dma_dest);
    for (unsigned i = 0; i < 64; ++i) check(dma_dest + i, dma_source[i]);
    uart_puts("DDR:DMA PASS\r\n");

    volatile uint32_t *code = (volatile uint32_t *)0x80008000u;
    for (unsigned i = 0; i < (unsigned)(ddr_probe_end - ddr_probe_start); ++i)
        code[i] = ddr_probe_start[i];
    __asm__ volatile ("fence rw,rw; fence.i" ::: "memory");
    // Repeated calls exercise TCM -> DDR -> TCM and a taken branch in DDR.
    for (unsigned i = 1; i <= 16; ++i) {
        uint32_t actual = ((uint32_t (*)(uint32_t))code)(i);
        uint32_t expected = (i * (i + 1)) >> 1;
        if (actual != expected) fail((uint32_t)code, expected, actual);
    }
    uart_puts("DDR:EXEC PASS\r\nDDR:PASS\r\n");
}

int main(void) {
    __asm__ volatile ("csrw mtvec,%0" :: "r"(ddr_trap));
    uart_puts("RV32 DDR bring-up (destructive), CPU 25 MHz\r\n");
    if (MEMINFO[0] != 0x44445231 || !(MEMINFO[1] & 1)) {
        uart_puts("DDR:DISABLED - use arty_s7_ddr_top\r\n");
        return 1;
    }
    uart_puts("DDR:WAIT calibration\r\n");
    uint32_t start = CLINT_MTIME_LO;
    while (!(MEMINFO[1] & 2)) {
        if ((uint32_t)(CLINT_MTIME_LO - start) > TIMEOUT_TICKS) {
            uart_puts("DDR:CALIBRATION TIMEOUT - check MIG clock/pins/reset\r\n");
            return 1;
        }
    }
    uart_puts("DDR:READY bytes="); hex(MEMINFO[3]); uart_newline();
    if (MEMINFO[2] != 0x80000000 || MEMINFO[3] != 0x10000000)
        fail(0x1000300C, 0x10000000, MEMINFO[3]);
    for (;;) {
        run_tests();
        uart_puts("R=repeat DDR test; BTN0=reset\r\n");
        while (uart_getc() != 'R') { }
    }
}
