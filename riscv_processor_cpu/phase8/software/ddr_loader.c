/* BRAM-resident UART loader for the isolated Arty S7 DDR project.
 * Protocol: 'U' or 'A', then "RDD1" + LE32 byte count + LE32 CRC32.
 * The payload is acknowledged every 16 bytes. 'G' runs a verified image.
 */
#include <stdint.h>
#include "soc.h"
#include "uart.h"

#define MEMINFO ((volatile uint32_t *)0x10003000u)
#define APP_BASE 0x80000000u
#define APP_MAX  (4u * 1024u * 1024u)
#define BLOCK_BYTES 16u
#define BYTE_TIMEOUT_TICKS 125000000u

static uint32_t loaded_size;

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
    if (!memory_ready()) { error("DDR"); return 0; }
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

__attribute__((noreturn)) static void run(void) {
    uart_puts("RDD1:GO\r\n");
    __asm__ volatile ("fence rw,rw; fence.i" ::: "memory");
    ((void (*)(void))APP_BASE)();
    for (;;) { }
}

int main(void) {
    uart_puts("RDD1:WAIT_DDR\r\n");
    while (!memory_ready()) { }
    uart_puts("RDD1:IDLE U=upload A=upload+run G=run I=info\r\n");
    for (;;) {
        char command = uart_getc();
        if (command == 'U' || command == 'A') {
            if (upload() && command == 'A') run();
        } else if (command == 'G') {
            if (loaded_size) run();
            else error("NO_IMAGE");
        } else if (command == 'I') {
            uart_puts("RDD1:INFO BASE=80000000 MAX=4194304 LOADED=");
            uart_print_int((int)loaded_size);
            uart_newline();
        }
    }
}
