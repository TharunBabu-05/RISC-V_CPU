/* BRAM-resident UART loader for the isolated Arty S7 DDR project.
 * U/A load an RDD1 application; W loads an RDDW WAD after the app.
 * Each transfer has a length and CRC32 and is acknowledged every 16 bytes.
 * G runs the app after placing verified WAD metadata in DDR.
 */
#include <stdint.h>
#include "soc.h"
#include "uart.h"
#include "ddr_wad_handoff.h"

#define MEMINFO ((volatile uint32_t *)0x10003000u)
#define APP_BASE 0x80000000u
#define APP_MAX  (4u * 1024u * 1024u)
#define WAD_BASE DDR_WAD_BASE
#define WAD_MAX  DDR_WAD_MAX
#define WAD_INFO ((volatile ddr_wad_handoff_t *)DDR_WAD_HANDOFF_ADDR)
#define BLOCK_BYTES 16u
#define FAST_WAD_BLOCK_BYTES 1024u
#define BYTE_TIMEOUT_TICKS 125000000u

static uint32_t loaded_size;
static uint32_t wad_size;

static int read_byte(uint8_t *value) {
    uint32_t start = CLINT_MTIME_LO;
    while (!(UART_STATUS & UART_RX_VALID)) {
        if ((uint32_t)(CLINT_MTIME_LO - start) >= BYTE_TIMEOUT_TICKS)
            return 0;
    }
    *value = (uint8_t)UART_RX;
    return 1;
}

static int read_u32(uint32_t *value) {
    uint8_t byte;
    *value = 0;
    for (unsigned i = 0; i < 4; ++i) {
        if (!read_byte(&byte)) return 0;
        *value |= (uint32_t)byte << (i * 8);
    }
    return 1;
}

static uint32_t crc_byte(uint32_t crc, uint8_t byte) {
    crc ^= byte;
    for (unsigned i = 0; i < 8; ++i)
        crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
    return crc;
}

static void error(const char *reason) {
    uart_puts("RDD1:ERR ");
    uart_puts(reason);
    uart_newline();
}

static int memory_ready(void) {
    return MEMINFO[0] == 0x44445231u &&
           (MEMINFO[1] & 3u) == 3u &&
           MEMINFO[2] == APP_BASE && MEMINFO[3] >= APP_MAX;
}

static int upload(void) {
    uint8_t magic[4], byte;
    uint32_t size, expected_crc, crc = 0xffffffffu;
    volatile uint8_t *const app = (volatile uint8_t *)APP_BASE;
    loaded_size = 0;
    wad_size = 0;
    if (!memory_ready()) { error("DDR"); return 0; }
    WAD_INFO->magic = 0;
    uart_puts("RDD1:READY\r\n");
    for (unsigned i = 0; i < 4; ++i)
        if (!read_byte(&magic[i])) { error("TIMEOUT"); return 0; }
    if (magic[0] != 'R' || magic[1] != 'D' ||
        magic[2] != 'D' || magic[3] != '1') {
        error("MAGIC"); return 0;
    }
    if (!read_u32(&size) || !read_u32(&expected_crc)) {
        error("TIMEOUT"); return 0;
    }
    if (!size || size > APP_MAX || size > MEMINFO[3]) {
        error("SIZE"); return 0;
    }
    uart_puts("RDD1:HEADER_OK\r\n");
    for (uint32_t offset = 0; offset < size; ++offset) {
        if (!read_byte(&byte)) { error("TIMEOUT"); return 0; }
        app[offset] = byte;
        if (((offset + 1u) % BLOCK_BYTES) == 0u || offset + 1u == size) {
            uart_puts("RDD1:NEXT ");
            uart_print_int((int)(offset + 1u));
            uart_newline();
        }
    }
    if (UART_STATUS & UART_RX_OVERFLOW) { error("OVERFLOW"); return 0; }
    __asm__ volatile ("fence rw,rw" ::: "memory");
    for (uint32_t offset = 0; offset < size; ++offset)
        crc = crc_byte(crc, app[offset]);
    if ((crc ^ 0xffffffffu) != expected_crc) { error("CRC"); return 0; }
    loaded_size = size;
    uart_puts("RDD1:OK\r\n");
    return 1;
}

static uint32_t wad_u32(const volatile uint8_t *data) {
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8) |
           ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

static int valid_wad(const volatile uint8_t *data, uint32_t size) {
    if (size < 12u || data[1] != 'W' || data[2] != 'A' || data[3] != 'D' ||
        (data[0] != 'I' && data[0] != 'P')) return 0;
    uint32_t count = wad_u32(data + 4);
    uint32_t directory = wad_u32(data + 8);
    if (directory > size || count > (size - directory) / 16u) return 0;
    for (uint32_t i = 0; i < count; ++i) {
        const volatile uint8_t *entry = data + directory + i * 16u;
        uint32_t position = wad_u32(entry);
        uint32_t length = wad_u32(entry + 4);
        if (length && (position > size || length > size - position)) return 0;
    }
    return 1;
}

static int upload_wad(uint32_t block_bytes) {
    uint8_t magic[4], byte;
    uint32_t size, expected_crc, crc = 0xffffffffu;
    volatile uint8_t *const wad = (volatile uint8_t *)WAD_BASE;
    wad_size = 0;
    if (!loaded_size || !memory_ready() || MEMINFO[3] < 0x04000000u) {
        error("WAD_STATE"); return 0;
    }
    WAD_INFO->magic = 0;
    uart_puts("RDDW:READY\r\n");
    for (unsigned i = 0; i < 4; ++i)
        if (!read_byte(&magic[i])) { error("TIMEOUT"); return 0; }
    if (magic[0] != 'R' || magic[1] != 'D' ||
        magic[2] != 'D' || magic[3] != 'W') {
        error("WAD_MAGIC"); return 0;
    }
    if (!read_u32(&size) || !read_u32(&expected_crc)) {
        error("TIMEOUT"); return 0;
    }
    if (size < 12u || size > WAD_MAX) { error("WAD_SIZE"); return 0; }
    uart_puts("RDDW:HEADER_OK\r\n");
    for (uint32_t offset = 0; offset < size; ++offset) {
        if (!read_byte(&byte)) { error("TIMEOUT"); return 0; }
        wad[offset] = byte;
        if (((offset + 1u) % block_bytes) == 0u || offset + 1u == size) {
            uart_puts("RDDW:NEXT ");
            uart_print_int((int)(offset + 1u));
            uart_newline();
        }
    }
    if (UART_STATUS & UART_RX_OVERFLOW) { error("OVERFLOW"); return 0; }
    __asm__ volatile ("fence rw,rw" ::: "memory");
    for (uint32_t offset = 0; offset < size; ++offset)
        crc = crc_byte(crc, wad[offset]);
    if ((crc ^ 0xffffffffu) != expected_crc) { error("WAD_CRC"); return 0; }
    if (!valid_wad(wad, size)) { error("WAD_FORMAT"); return 0; }
    WAD_INFO->base = WAD_BASE;
    WAD_INFO->size = size;
    WAD_INFO->crc32 = expected_crc;
    __asm__ volatile ("fence rw,rw" ::: "memory");
    WAD_INFO->magic = DDR_WAD_HANDOFF_MAGIC;
    wad_size = size;
    uart_puts("RDDW:OK\r\n");
    return 1;
}

__attribute__((noreturn)) static void run(void) {
    uart_puts("RDD1:GO\r\n");
    __asm__ volatile ("fence rw,rw; fence.i" ::: "memory");
    ((void (*)(void))APP_BASE)();
    for (;;) { }
}

int main(void) {
    uart_puts("RDD1:WAIT_DDR\r\n");
    while (!memory_ready()) { }
    WAD_INFO->magic = 0;
    uart_puts("RDD1:IDLE U=upload A=upload+run W=wad F=fast-wad G=run I=info J=wad-info K=caps\r\n");
    for (;;) {
        char command = uart_getc();
        if (command == 'U' || command == 'A') {
            if (upload() && command == 'A') run();
        } else if (command == 'W') {
            upload_wad(BLOCK_BYTES);
        } else if (command == 'F') {
            upload_wad(FAST_WAD_BLOCK_BYTES);
        } else if (command == 'G') {
            if (loaded_size) run();
            else error("NO_IMAGE");
        } else if (command == 'I') {
            uart_puts("RDD1:INFO BASE=80000000 MAX=4194304 LOADED=");
            uart_print_int((int)loaded_size);
            uart_newline();
        } else if (command == 'J') {
            uart_puts("RDDW:INFO BASE=82000000 MAX=33554432 LOADED=");
            uart_print_int((int)wad_size);
            uart_newline();
        } else if (command == 'K') {
            uart_puts("RDDW:CAPS FAST_BLOCK=1024\r\n");
        }
    }
}
