#include "doom_stream.h"
#include "uart.h"

#define SOURCE_WIDTH 320u
#define SOURCE_HEIGHT 200u

static uint8_t payload[DOOM_STREAM_PIXELS];

uint32_t doom_stream_crc32(const uint8_t *data, unsigned size) {
    static const uint32_t table[16] = {
        0x00000000u, 0x1db71064u, 0x3b6e20c8u, 0x26d930acu,
        0x76dc4190u, 0x6b6b51f4u, 0x4db26158u, 0x5005713cu,
        0xedb88320u, 0xf00f9344u, 0xd6d6a3e8u, 0xcb61b38cu,
        0x9b64c2b0u, 0x86d3d2d4u, 0xa00ae278u, 0xbdbdf21cu
    };
    uint32_t crc = 0xffffffffu;
    for (unsigned i = 0; i < size; ++i) {
        crc ^= data[i];
        crc = (crc >> 4) ^ table[crc & 15u];
        crc = (crc >> 4) ^ table[crc & 15u];
    }
    return ~crc;
}

static void send_u16(uint16_t value) {
    uart_putc((char)value);
    uart_putc((char)(value >> 8));
}

static void send_u32(uint32_t value) {
    for (unsigned shift = 0; shift < 32; shift += 8)
        uart_putc((char)(value >> shift));
}

static void send_payload(uint16_t sequence) {
    uint32_t crc = doom_stream_crc32(payload, DOOM_STREAM_PIXELS);
    uart_putc('R'); uart_putc('V'); uart_putc('F'); uart_putc('1');
    uart_putc((char)DOOM_STREAM_WIDTH);
    uart_putc((char)DOOM_STREAM_HEIGHT);
    send_u16(sequence);
    send_u32(crc);
    for (unsigned i = 0; i < DOOM_STREAM_PIXELS; ++i)
        uart_putc((char)payload[i]);
}

void doom_stream_send_indexed(const uint8_t *framebuffer,
                              const uint8_t palette[256], uint16_t sequence) {
    for (unsigned y = 0; y < DOOM_STREAM_HEIGHT; ++y) {
        unsigned sy = (2u * y + 1u) * SOURCE_HEIGHT / (2u * DOOM_STREAM_HEIGHT);
        for (unsigned x = 0; x < DOOM_STREAM_WIDTH; ++x) {
            unsigned sx = (2u * x + 1u) * SOURCE_WIDTH / (2u * DOOM_STREAM_WIDTH);
            payload[y * DOOM_STREAM_WIDTH + x] = palette[framebuffer[sy * SOURCE_WIDTH + sx]];
        }
    }
    send_payload(sequence);
}

void doom_stream_send(const uint32_t *framebuffer, uint16_t sequence) {
    for (unsigned y = 0; y < DOOM_STREAM_HEIGHT; ++y) {
        unsigned source_y = (2u * y + 1u) * SOURCE_HEIGHT /
                            (2u * DOOM_STREAM_HEIGHT);
        for (unsigned x = 0; x < DOOM_STREAM_WIDTH; ++x) {
            unsigned source_x = (2u * x + 1u) * SOURCE_WIDTH /
                                (2u * DOOM_STREAM_WIDTH);
            uint32_t pixel = framebuffer[source_y * SOURCE_WIDTH + source_x];
            uint8_t r = (uint8_t)((pixel >> 16) & 0xffu);
            uint8_t g = (uint8_t)((pixel >> 8) & 0xffu);
            uint8_t b = (uint8_t)(pixel & 0xffu);
            payload[y * DOOM_STREAM_WIDTH + x] =
                (uint8_t)((r & 0xe0u) | ((g >> 3) & 0x1cu) | (b >> 6));
        }
    }

    send_payload(sequence);
}
