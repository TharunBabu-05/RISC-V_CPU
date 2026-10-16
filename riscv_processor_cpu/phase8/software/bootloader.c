/* Resident QSPI/UART recovery bootloader for the Phase 8 FPGA SoC.
 *
 * Protocol, all multi-byte fields little-endian:
 *   Host -> 'U'                         begin upload, remain in loader
 *        or 'A'                         begin upload, run on success
 *   CPU  -> "RVBL:READY\r\n"
 *   Host -> "RVBL" + u32 size + u32 CRC32
 *   CPU  -> "RVBL:HEADER_OK\r\n"
 *   Host -> application in blocks of up to 32 bytes
 *   CPU  -> "RVBL:NEXT <received-bytes>\r\n" after each block
 *   CPU  -> "RVBL:OK\r\n" or "RVBL:ERR ...\r\n"
 *
 * 'G' jumps to an image already present at APP_BASE. 'I' prints loader info.
 */

#include <stdint.h>

#include "soc.h"
#include "qspi.h"
#include "uart.h"

#define APP_BASE       0x00004000UL
#define BRAM_END       0x00010000UL
#define APP_MAX_BYTES  (BRAM_END - APP_BASE)
#define CRC32_POLY     0xEDB88320UL
#define TRANSFER_BLOCK_BYTES 32U
#define FLASH_IMAGE_OFFSET   0x00400000UL
#define FLASH_IMAGE_MAGIC    0x31465652UL /* bytes "RVF1" */
#define FLASH_HEADER_BYTES   16U

static uint32_t uploaded_size;

static uint8_t get_byte(void) {
    return (uint8_t)uart_getc();
}

static uint32_t get_u32_le(void) {
    uint32_t value = 0;
    value |= (uint32_t)get_byte();
    value |= (uint32_t)get_byte() << 8;
    value |= (uint32_t)get_byte() << 16;
    value |= (uint32_t)get_byte() << 24;
    return value;
}

static uint32_t crc32_byte(uint32_t crc, uint8_t data) {
    unsigned int bit;

    crc ^= data;
    for (bit = 0; bit < 8; ++bit) {
        uint32_t mask = 0U - (crc & 1U);
        crc = (crc >> 1) ^ (CRC32_POLY & mask);
    }
    return crc;
}

static const char *load_flash_image(void) {
    volatile uint8_t *destination = (volatile uint8_t *)APP_BASE;
    uint32_t size;
    uint32_t expected_crc;
    uint32_t entry;
    uint32_t actual_crc = 0xFFFFFFFFUL;
    uint32_t offset;

    /* A failed flash attempt must never leave a runnable partial image. */
    uploaded_size = 0;

    if (qspi_read_u32_le(FLASH_IMAGE_OFFSET) != FLASH_IMAGE_MAGIC)
        return "MAGIC";

    size = qspi_read_u32_le(FLASH_IMAGE_OFFSET + 4U);
    expected_crc = qspi_read_u32_le(FLASH_IMAGE_OFFSET + 8U);
    entry = qspi_read_u32_le(FLASH_IMAGE_OFFSET + 12U);
    if (size == 0U || size > APP_MAX_BYTES)
        return "SIZE";
    if (entry != APP_BASE)
        return "ENTRY";

    for (offset = 0; offset < size; ++offset) {
        uint8_t byte = qspi_read_byte(FLASH_IMAGE_OFFSET +
                                      FLASH_HEADER_BYTES + offset);
        destination[offset] = byte;
        actual_crc = crc32_byte(actual_crc, byte);
    }
    actual_crc ^= 0xFFFFFFFFUL;
    if (actual_crc != expected_crc)
        return "CRC";

    uploaded_size = size;
    return 0;
}

static int try_flash_boot(void) {
    const char *error;

    uart_puts("RVBL:FLASH_CHECK");
    uart_newline();
    error = load_flash_image();
    if (error) {
        uart_puts("RVBL:FLASH_INVALID ");
        uart_puts(error);
        uart_newline();
        return 0;
    }

    uart_puts("RVBL:FLASH_OK");
    uart_newline();
    return 1;
}

static void print_info(void) {
    uart_puts("RVBL:INFO APP=0x00004000 MAX=49152 LOADED=");
    uart_print_int((int)uploaded_size);
    uart_newline();
}

__attribute__((noreturn))
static void run_application(void) {
    void (*entry)(void) = (void (*)(void))APP_BASE;

    uart_puts("RVBL:GO");
    uart_newline();

    __asm__ volatile (
        "csrw mie, zero\n"
        "fence.i\n"
        ::: "memory"
    );

    entry();
    for (;;) { }
}

static int receive_image(void) {
    volatile uint8_t *destination = (volatile uint8_t *)APP_BASE;
    uint32_t expected_size;
    uint32_t expected_crc;
    uint32_t actual_crc = 0xFFFFFFFFUL;
    uint32_t offset;

    uart_puts("RVBL:READY");
    uart_newline();

    if (get_byte() != 'R' || get_byte() != 'V' ||
        get_byte() != 'B' || get_byte() != 'L') {
        uart_puts("RVBL:ERR MAGIC");
        uart_newline();
        return 0;
    }

    expected_size = get_u32_le();
    expected_crc = get_u32_le();
    if (expected_size == 0 || expected_size > APP_MAX_BYTES) {
        uart_puts("RVBL:ERR SIZE");
        uart_newline();
        return 0;
    }

    uart_puts("RVBL:HEADER_OK");
    uart_newline();

    offset = 0;
    while (offset < expected_size) {
        uint32_t block_end = offset + TRANSFER_BLOCK_BYTES;
        if (block_end > expected_size)
            block_end = expected_size;

        while (offset < block_end) {
            uint8_t byte = get_byte();
            destination[offset] = byte;
            actual_crc = crc32_byte(actual_crc, byte);
            ++offset;
        }

        uart_puts("RVBL:NEXT ");
        uart_print_int((int)offset);
        uart_newline();
    }
    actual_crc ^= 0xFFFFFFFFUL;

    if (actual_crc != expected_crc) {
        uploaded_size = 0;
        uart_puts("RVBL:ERR CRC");
        uart_newline();
        return 0;
    }

    uploaded_size = expected_size;
    uart_puts("RVBL:OK");
    uart_newline();
    return 1;
}

int main(void) {
    uart_init();
    uart_newline();
    uart_puts("RV32 QSPI Boot ROM v3");
    uart_newline();

    if (try_flash_boot())
        run_application();

    uart_puts("UART recovery mode");
    uart_newline();
    uart_puts("U=upload  A=upload+run  G=run  F=flash retry  I=info");
    uart_newline();
    uart_puts("RVBL:IDLE");
    uart_newline();

    for (;;) {
        char command = uart_getc();

        if (command == 'U' || command == 'u') {
            (void)receive_image();
        } else if (command == 'A' || command == 'a') {
            if (receive_image())
                run_application();
        } else if (command == 'G' || command == 'g') {
            if (uploaded_size != 0U) {
                run_application();
            } else {
                uart_puts("RVBL:ERR NO_IMAGE");
                uart_newline();
            }
        } else if (command == 'F' || command == 'f') {
            if (try_flash_boot())
                run_application();
        } else if (command == 'I' || command == 'i') {
            print_info();
        } else if (command == '\r' || command == '\n') {
            /* Ignore terminal line endings. */
        } else {
            uart_puts("RVBL:ERR COMMAND");
            uart_newline();
        }
    }
}
