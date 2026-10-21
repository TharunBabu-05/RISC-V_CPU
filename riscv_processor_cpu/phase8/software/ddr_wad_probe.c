#include <stdint.h>
#include "uart.h"
#include "ddr_wad_handoff.h"

static uint32_t read_u32(const volatile uint8_t *data) {
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8) |
           ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

static int name_is(const volatile uint8_t *name, const char *expected) {
    for (unsigned i = 0; i < 8; ++i) {
        uint8_t ch = expected[i] ? (uint8_t)expected[i] : 0;
        if (name[i] != ch) return 0;
        if (!ch) {
            for (++i; i < 8; ++i)
                if (name[i]) return 0;
            return 1;
        }
    }
    return expected[8] == 0;
}

static void fail(const char *reason) {
    uart_puts("WAD_PROBE:FAIL ");
    uart_puts(reason);
    uart_newline();
    for (;;) { }
}

int main(void) {
    volatile const ddr_wad_handoff_t *const info =
        (volatile const ddr_wad_handoff_t *)DDR_WAD_HANDOFF_ADDR;
    if (info->magic != DDR_WAD_HANDOFF_MAGIC ||
        info->base != DDR_WAD_BASE ||
        info->size < 12u || info->size > DDR_WAD_MAX)
        fail("HANDOFF");

    const volatile uint8_t *const wad = (const volatile uint8_t *)DDR_WAD_BASE;
    if ((wad[0] != 'I' && wad[0] != 'P') ||
        wad[1] != 'W' || wad[2] != 'A' || wad[3] != 'D')
        fail("MAGIC");

    uint32_t count = read_u32(wad + 4);
    uint32_t directory = read_u32(wad + 8);
    if (directory > info->size || count > (info->size - directory) / 16u)
        fail("DIRECTORY");

    unsigned e1m1 = 0, playpal = 0, pnames = 0;
    uint32_t sample = 0;
    for (uint32_t i = 0; i < count; ++i) {
        const volatile uint8_t *entry = wad + directory + i * 16u;
        uint32_t offset = read_u32(entry);
        uint32_t length = read_u32(entry + 4);
        if (length && (offset > info->size || length > info->size - offset))
            fail("LUMP_BOUNDS");
        e1m1 |= name_is(entry + 8, "E1M1");
        playpal |= name_is(entry + 8, "PLAYPAL");
        pnames |= name_is(entry + 8, "PNAMES");
        if (length) sample ^= (uint32_t)wad[offset] ^ (uint32_t)wad[offset + length - 1u];
    }

    uart_puts("WAD_PROBE:PASS type=");
    uart_puts(wad[0] == 'I' ? "IWAD" : "PWAD");
    uart_puts(" lumps="); uart_print_int((int)count);
    uart_puts(" bytes="); uart_print_int((int)info->size);
    uart_puts(" E1M1="); uart_print_int((int)e1m1);
    uart_puts(" PLAYPAL="); uart_print_int((int)playpal);
    uart_puts(" PNAMES="); uart_print_int((int)pnames);
    uart_puts(" sample="); uart_print_int((int)sample);
    uart_newline();
    for (;;) { }
}
