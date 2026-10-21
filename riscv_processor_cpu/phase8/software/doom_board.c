#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ddr_wad_handoff.h"
#include "doom_stream.h"
#include "soc.h"
#include "uart.h"
#include "doomgeneric.h"
#ifdef DOOM_DIRECT_VIDEO
#include "i_video.h"
#include "tables.h"
#include "r_main.h"
extern int usegamma;
static uint8_t stream_palette[256];
void __real_I_SetPalette(byte *palette);
void __real_R_RenderPlayerView(player_t *player);
#endif

static uint16_t frame_sequence;
static int release_prefix;
static uint32_t previous_frame_end;
static uint32_t render_ticks_total;
static uint32_t stream_ticks_total;
static uint32_t sleep_ticks_total, view_ticks_total;
static uint32_t previous_cycle, previous_instret;
static uint64_t engine_cycles_total, engine_instructions_total;
static unsigned interval_count;

static uint32_t cpu_cycles(void) {
    uint32_t value;
    __asm__ volatile ("rdcycle %0" : "=r"(value));
    return value;
}

static uint32_t cpu_instructions(void) {
    uint32_t value;
    __asm__ volatile ("rdinstret %0" : "=r"(value));
    return value;
}

static void print_unsigned(uint32_t value) {
    char digits[10];
    unsigned count = 0;
    do {
        digits[count++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value != 0);
    while (count != 0) uart_putc(digits[--count]);
}

static uint32_t ticks_ms(void) {
    uint32_t hi, lo, check;
    do {
        hi = CLINT_MTIME_HI;
        lo = CLINT_MTIME_LO;
        check = CLINT_MTIME_HI;
    } while (hi != check);
    return (uint32_t)((((uint64_t)hi << 32) | lo) / 25000u);
}

void DG_Init(void) {
    uart_puts("DOOM:VIDEO RVF1 80x50 RGB332\r\n");
#ifdef DOOM_DIRECT_VIDEO
    uart_puts("DOOM:VIDEO_PATH DIRECT_INDEXED\r\n");
#endif
}

void DG_DrawFrame(void) {
    uint32_t start = CLINT_MTIME_LO;
    if (previous_frame_end != 0) {
        render_ticks_total += start - previous_frame_end;
        engine_cycles_total += (uint32_t)(cpu_cycles() - previous_cycle);
        engine_instructions_total += (uint32_t)(cpu_instructions() - previous_instret);
        ++interval_count;
    }
#ifdef DOOM_DIRECT_VIDEO
    doom_stream_send_indexed(I_VideoBuffer, stream_palette, frame_sequence++);
#else
    doom_stream_send(DG_ScreenBuffer, frame_sequence++);
#endif
    uint32_t end = CLINT_MTIME_LO;
    stream_ticks_total += end - start;
    previous_frame_end = end;
    if ((frame_sequence & 7u) == 0u) {
        uart_puts("\r\nDOOM:PERF render_us=");
        print_unsigned(interval_count ? render_ticks_total / (25u * interval_count) : 0);
        uart_puts(" stream_us=");
        print_unsigned(stream_ticks_total / 200u);
        uart_puts(" view_us=");
        print_unsigned(view_ticks_total / 200u);
        uart_puts(" sleep_us=");
        print_unsigned(sleep_ticks_total / 200u);
        uart_puts(" engine_cpi_x100=");
        print_unsigned(engine_instructions_total ?
            (uint32_t)(engine_cycles_total * 100u / engine_instructions_total) : 0);
        uart_puts(" engine_instructions=");
        print_unsigned(interval_count ?
            (uint32_t)(engine_instructions_total / interval_count) : 0);
        uart_puts(" (8-frame window)\r\n");
        render_ticks_total = 0;
        stream_ticks_total = 0;
        sleep_ticks_total = 0;
        view_ticks_total = 0;
        engine_cycles_total = 0;
        engine_instructions_total = 0;
        interval_count = 0;
    }
    // Exclude diagnostic UART output from the next engine interval.
    previous_frame_end = CLINT_MTIME_LO;
    previous_cycle = cpu_cycles();
    previous_instret = cpu_instructions();
}

#ifdef DOOM_DIRECT_VIDEO
// Linker wrappers keep the upstream checkout unchanged. All engine palette
// changes, including damage flashes and gamma, update the sampled RGB332 LUT.
void __wrap_I_SetPalette(byte *palette) {
    __real_I_SetPalette(palette);
    for (unsigned i = 0; i < 256; ++i) {
        unsigned r = gammatable[usegamma][palette[i * 3]];
        unsigned g = gammatable[usegamma][palette[i * 3 + 1]];
        unsigned b = gammatable[usegamma][palette[i * 3 + 2]];
        stream_palette[i] = (r & 0xe0u) | ((g >> 3) & 0x1cu) | (b >> 6);
    }
}

void __wrap_I_FinishUpdate(void) { DG_DrawFrame(); }

void __wrap_R_RenderPlayerView(player_t *player) {
    uint32_t start = CLINT_MTIME_LO;
    __real_R_RenderPlayerView(player);
    view_ticks_total += CLINT_MTIME_LO - start;
}
#endif

void DG_SleepMs(uint32_t ms) {
    uint32_t begin = CLINT_MTIME_LO;
    uint32_t start = ticks_ms();
    while ((uint32_t)(ticks_ms() - start) < ms) { }
    sleep_ticks_total += CLINT_MTIME_LO - begin;
}

uint32_t DG_GetTicksMs(void) { return ticks_ms(); }

int DG_GetKey(int *pressed, unsigned char *key) {
    while (uart_kbhit()) {
        unsigned char received = (unsigned char)uart_getc();
        if (received == 0xf0u && !release_prefix) {
            release_prefix = 1;
            continue;
        }
        *pressed = !release_prefix;
        *key = received;
        release_prefix = 0;
        return 1;
    }
    return 0;
}

void DG_SetWindowTitle(const char *title) { (void)title; }

static void print_hex(uint32_t value) {
    static const char digits[] = "0123456789ABCDEF";
    for (int shift = 28; shift >= 0; shift -= 4)
        uart_putc(digits[(value >> shift) & 15u]);
}

__attribute__((noreturn)) void doom_board_trap(uint32_t cause, uint32_t pc,
                                                uint32_t value) {
    uart_puts("\r\nDOOM:TRAP cause=");
    print_hex(cause);
    uart_puts(" pc=");
    print_hex(pc);
    uart_puts(" value=");
    print_hex(value);
    uart_newline();
    for (;;) { }
}

int main(void) {
    const ddr_wad_handoff_t *info =
        (const ddr_wad_handoff_t *)DDR_WAD_HANDOFF_ADDR;
    if (info->magic != DDR_WAD_HANDOFF_MAGIC || info->base != DDR_WAD_BASE ||
        info->size < 12 || info->size > DDR_WAD_MAX) {
        uart_puts("DOOM:ERR NO_WAD\r\n");
        for (;;) { }
    }
    uart_puts("DOOM:BOOT DDR IWAD\r\n");
    FILE *wad = fopen("doom1.wad", "rb");
    char magic[4];
    if (!wad || fread(magic, 1, sizeof(magic), wad) != sizeof(magic) ||
        (magic[0] != 'I' && magic[0] != 'P') ||
        magic[1] != 'W' || magic[2] != 'A' || magic[3] != 'D') {
        uart_puts("DOOM:ERR WAD_OPEN\r\n");
        for (;;) { }
    }
    fclose(wad);
    uart_puts("DOOM:WAD_OK\r\n");
    setvbuf(stdout, 0, _IONBF, 0);
    char *argv[] = { "doom", "-iwad", "doom1.wad", "-nosound", "-nomusic",
                     "-mb", "6", "-warp", "1", "1", 0 };
    doomgeneric_Create(10, argv);
    for (;;) doomgeneric_Tick();
}
