#ifndef DOOM_WAD_ART_H
#define DOOM_WAD_ART_H

#include <stdint.h>

typedef struct {
    uint32_t offset;
    uint32_t size;
} doom_lump_t;

/* 1 = found, 0 = absent, -1 = malformed WAD. Last duplicate wins. */
int doom_find_lump(const volatile uint8_t *wad, uint32_t wad_size,
                   const char *name, doom_lump_t *result);

/* Decode a DOOM column-post patch into an 8-bit indexed image. */
int doom_decode_patch(const volatile uint8_t *patch, uint32_t patch_size,
                      uint8_t *pixels, uint16_t width, uint16_t height);

#endif
