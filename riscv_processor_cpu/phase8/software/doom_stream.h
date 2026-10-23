#ifndef DOOM_STREAM_H
#define DOOM_STREAM_H

#include <stdint.h>

#ifndef DOOM_STREAM_WIDTH
#define DOOM_STREAM_WIDTH 80u
#endif
#ifndef DOOM_STREAM_HEIGHT
#define DOOM_STREAM_HEIGHT 50u
#endif
#define DOOM_STREAM_PIXELS (DOOM_STREAM_WIDTH * DOOM_STREAM_HEIGHT)

uint32_t doom_stream_crc32(const uint8_t *data, unsigned size);
void doom_stream_send(const uint32_t *framebuffer, uint16_t sequence);
void doom_stream_send_indexed(const uint8_t *framebuffer,
                              const uint8_t palette[256], uint16_t sequence);
void doom_stream_reset(void);
unsigned doom_stream_last_bytes(void);

#endif
