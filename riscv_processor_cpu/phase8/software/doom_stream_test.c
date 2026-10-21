#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "doom_stream.h"

static uint32_t framebuffer[320u * 200u];
static uint8_t wire[12u + DOOM_STREAM_PIXELS];
static unsigned wire_size;
static uint8_t indexed[320u * 200u];
static uint8_t palette[256], reference[12u + DOOM_STREAM_PIXELS];

static uint32_t slow_crc(const uint8_t *data, unsigned size) {
    uint32_t crc = ~0u;
    while (size--) {
        crc ^= *data++;
        for (unsigned b = 0; b < 8; ++b)
            crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
    }
    return ~crc;
}

void uart_putc(char byte) {
    assert(wire_size < sizeof(wire));
    wire[wire_size++] = (uint8_t)byte;
}

int main(void) {
    assert(doom_stream_crc32((const uint8_t *)"123456789", 9) == 0xcbf43926u);
    framebuffer[2u * 320u + 2u] = 0x00ff0000u;
    framebuffer[2u * 320u + 6u] = 0x0000ff00u;
    framebuffer[6u * 320u + 2u] = 0x000000ffu;
    doom_stream_send(framebuffer, 0x1234u);
    assert(wire_size == sizeof(wire));
    assert(memcmp(wire, "RVF1", 4) == 0);
    assert(wire[4] == DOOM_STREAM_WIDTH && wire[5] == DOOM_STREAM_HEIGHT);
    assert(wire[6] == 0x34 && wire[7] == 0x12);
    assert(wire[12] == 0xe0 && wire[13] == 0x1c && wire[12 + 80] == 0x03);
    uint32_t crc = (uint32_t)wire[8] | ((uint32_t)wire[9] << 8) |
                   ((uint32_t)wire[10] << 16) | ((uint32_t)wire[11] << 24);
    assert(crc == doom_stream_crc32(wire + 12, DOOM_STREAM_PIXELS));
    // Match the former full RGB conversion byte-for-byte, including palette
    // updates, sequence wrap, all palette indices and discarded source pixels.
    for (unsigned pass = 0; pass < 8; ++pass) {
        uint32_t rgb[256];
        for (unsigned i = 0; i < 256; ++i) {
            unsigned r = (i * 17u + pass * 31u) & 255u;
            unsigned g = (i * 43u + pass * 13u) & 255u;
            unsigned b = (i * 67u + pass * 7u) & 255u;
            rgb[i] = (r << 16) | (g << 8) | b;
            palette[i] = (r & 0xe0u) | ((g >> 3) & 0x1cu) | (b >> 6);
        }
        for (unsigned i = 0; i < 320u * 200u; ++i) {
            indexed[i] = (uint8_t)(i * 7u + i / 320u + pass);
            framebuffer[i] = rgb[indexed[i]];
        }
        wire_size = 0;
        doom_stream_send(framebuffer, (uint16_t)(65532u + pass));
        memcpy(reference, wire, sizeof(wire));
        wire_size = 0;
        doom_stream_send_indexed(indexed, palette, (uint16_t)(65532u + pass));
        assert(wire_size == sizeof(wire));
        assert(memcmp(reference, wire, sizeof(wire)) == 0);
        assert(slow_crc(wire + 12, DOOM_STREAM_PIXELS) ==
               doom_stream_crc32(wire + 12, DOOM_STREAM_PIXELS));
    }
    return 0;
}
