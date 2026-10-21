#include <stdint.h>
#include "uart.h"
#include "ddr_wad_handoff.h"
#include "doom_wad_art.h"

#define SCREEN_W 320u
#define SCREEN_H 200u
#define TERM_COLS 79u
#define TERM_ROWS 24u

static uint8_t picture[SCREEN_W * SCREEN_H];

static void fail(const char *reason) {
    uart_puts("TITLEPIC:FAIL ");
    uart_puts(reason);
    uart_newline();
    for (;;) { }
}

static void color(int foreground, const volatile uint8_t *palette, uint8_t index) {
    const volatile uint8_t *rgb = palette + 3u * index;
    uart_putc('\033');
    uart_puts(foreground ? "[38;2;" : "[48;2;");
    uart_print_int(rgb[0]); uart_putc(';');
    uart_print_int(rgb[1]); uart_putc(';');
    uart_print_int(rgb[2]); uart_putc('m');
}

int main(void) {
    const volatile ddr_wad_handoff_t *const info =
        (const volatile ddr_wad_handoff_t *)DDR_WAD_HANDOFF_ADDR;
    if (info->magic != DDR_WAD_HANDOFF_MAGIC ||
        info->base != DDR_WAD_BASE || info->size < 12u || info->size > DDR_WAD_MAX)
        fail("HANDOFF");

    const volatile uint8_t *const wad = (const volatile uint8_t *)DDR_WAD_BASE;
    doom_lump_t palette_lump, title_lump;
    if (doom_find_lump(wad, info->size, "PLAYPAL", &palette_lump) != 1 ||
        palette_lump.size < 768u) fail("PLAYPAL");
    if (doom_find_lump(wad, info->size, "TITLEPIC", &title_lump) != 1)
        fail("TITLEPIC");
    if (!doom_decode_patch(wad + title_lump.offset, title_lump.size,
                           picture, SCREEN_W, SCREEN_H)) fail("PATCH");

    const volatile uint8_t *const palette = wad + palette_lump.offset;
    uart_puts("\033[?25l\033[2J\033[H");
    for (unsigned row = 0; row < TERM_ROWS; ++row) {
        uart_move_cursor((int)row + 1, 1);
        for (unsigned col = 0; col < TERM_COLS; ++col) {
            unsigned x = col * 4u + 2u;
            unsigned y = row * 8u + 2u;
            color(1, palette, picture[y * SCREEN_W + x]);
            color(0, palette, picture[(y + 4u) * SCREEN_W + x]);
            uart_putc((char)0xe2); uart_putc((char)0x96); uart_putc((char)0x80);
        }
    }
    uart_puts("\033[0m\033[25;1HTITLEPIC:PASS DDR IWAD -> ANSI terminal\033[?25h");
    for (;;) { }
}
