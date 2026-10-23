#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "doom_stream.h"

static uint32_t framebuffer[320u * 200u];
static uint8_t wire[18u + DOOM_STREAM_PIXELS];
static unsigned wire_size;
static uint8_t indexed[320u * 200u];
static uint8_t palette[256], reference[18u + DOOM_STREAM_PIXELS];

static uint32_t slow_crc(const uint8_t *data, unsigned size) {
    uint32_t crc = ~0u;
    while (size--) {
        crc ^= *data++;
        for (unsigned b = 0; b < 8; ++b)
            crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
    }
    return ~crc;
}

static unsigned decode_frame(uint8_t *decoded, const uint8_t *previous) {
    assert(doom_stream_last_bytes() == wire_size);
    uint32_t wire_bytes = (uint32_t)wire[14] | ((uint32_t)wire[15] << 8) |
                          ((uint32_t)wire[16] << 16) | ((uint32_t)wire[17] << 24);
    assert(wire_size == 18u + wire_bytes);
    if (!(wire[8] & 1u)) {
        assert(wire_bytes == DOOM_STREAM_PIXELS);
        memcpy(decoded, wire + 18, wire_bytes);
    } else {
        unsigned src = 18, dst = 0;
        while (src < wire_size) {
            unsigned control = wire[src++];
            unsigned count = (control & 0x7fu) + 1u;
            assert(dst + count <= DOOM_STREAM_PIXELS);
            if (control & 0x80u) {
                assert(src < wire_size);
                memset(decoded + dst, wire[src++], count);
            } else {
                assert(src + count <= wire_size);
                memcpy(decoded + dst, wire + src, count);
                src += count;
            }
            dst += count;
        }
        assert(dst == DOOM_STREAM_PIXELS);
    }
    if (wire[8] & 2u) {
        assert(previous != NULL);
        for (unsigned i = 0; i < DOOM_STREAM_PIXELS; ++i)
            decoded[i] ^= previous[i];
    }
    return DOOM_STREAM_PIXELS;
}

void uart_putc(char byte) {
    assert(wire_size < sizeof(wire));
    wire[wire_size++] = (uint8_t)byte;
}

int main(void) {
    doom_stream_reset();
    assert(doom_stream_crc32((const uint8_t *)"123456789", 9) == 0xcbf43926u);
    unsigned sx0 = 320u / (2u * DOOM_STREAM_WIDTH);
    unsigned sx1 = 3u * 320u / (2u * DOOM_STREAM_WIDTH);
    unsigned sy0 = 200u / (2u * DOOM_STREAM_HEIGHT);
    unsigned sy1 = 3u * 200u / (2u * DOOM_STREAM_HEIGHT);
    framebuffer[sy0 * 320u + sx0] = 0x00ff0000u;
    framebuffer[sy0 * 320u + sx1] = 0x0000ff00u;
    framebuffer[sy1 * 320u + sx0] = 0x000000ffu;
    doom_stream_send(framebuffer, 0x1234u);
    assert(wire_size <= sizeof(wire));
    assert(memcmp(wire, "RVF2", 4) == 0);
    assert(wire[4] == DOOM_STREAM_WIDTH && wire[5] == DOOM_STREAM_HEIGHT);
    assert(wire[6] == 0x34 && wire[7] == 0x12);
    assert(wire[8] == 1 && wire[9] == 0);
    uint32_t crc = (uint32_t)wire[10] | ((uint32_t)wire[11] << 8) |
                   ((uint32_t)wire[12] << 16) | ((uint32_t)wire[13] << 24);
    uint8_t decoded[DOOM_STREAM_PIXELS];
    assert(decode_frame(decoded, NULL) == DOOM_STREAM_PIXELS);
    assert(decoded[0] == 0xe0 && decoded[1] == 0x1c &&
           decoded[DOOM_STREAM_WIDTH] == 0x03);
    assert(crc == doom_stream_crc32(decoded, DOOM_STREAM_PIXELS));
    uint8_t previous[DOOM_STREAM_PIXELS];
    memcpy(previous, decoded, sizeof(previous));
    wire_size = 0;
    doom_stream_send(framebuffer, 0x1235u);
    assert((wire[8] & 3u) == 3u);
    assert(decode_frame(decoded, previous) == DOOM_STREAM_PIXELS);
    assert(memcmp(decoded, previous, sizeof(previous)) == 0);
    framebuffer[sy0 * 320u + sx0] = 0;
    wire_size = 0;
    doom_stream_send(framebuffer, 0x1236u);
    assert((wire[8] & 3u) == 3u);
    assert(decode_frame(decoded, previous) == DOOM_STREAM_PIXELS);
    assert(decoded[0] == 0 &&
           doom_stream_crc32(decoded, DOOM_STREAM_PIXELS) ==
               ((uint32_t)wire[10] | ((uint32_t)wire[11] << 8) |
                ((uint32_t)wire[12] << 16) | ((uint32_t)wire[13] << 24)));
    memcpy(previous, decoded, sizeof(previous));
    wire_size = 0;
    doom_stream_send(framebuffer, 0x1240u);
    assert((wire[8] & 2u) == 0u);
    assert(decode_frame(decoded, NULL) == DOOM_STREAM_PIXELS);
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
        doom_stream_reset();
        doom_stream_send(framebuffer, (uint16_t)(65532u + pass));
        memcpy(reference, wire, sizeof(wire));
        assert(decode_frame(decoded, NULL) == DOOM_STREAM_PIXELS);
        uint32_t frame_crc = (uint32_t)wire[10] | ((uint32_t)wire[11] << 8) |
                             ((uint32_t)wire[12] << 16) | ((uint32_t)wire[13] << 24);
        assert(slow_crc(decoded, DOOM_STREAM_PIXELS) == frame_crc);
        wire_size = 0;
        doom_stream_reset();
        doom_stream_send_indexed(indexed, palette, (uint16_t)(65532u + pass));
        assert(wire_size <= sizeof(wire));
        assert(memcmp(reference, wire, sizeof(wire)) == 0);
        assert(decode_frame(decoded, NULL) == DOOM_STREAM_PIXELS);
        assert(slow_crc(decoded, DOOM_STREAM_PIXELS) == frame_crc);
    }
    return 0;
}
