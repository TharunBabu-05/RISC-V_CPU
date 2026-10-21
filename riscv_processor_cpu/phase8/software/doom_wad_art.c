#include "doom_wad_art.h"

static uint32_t le32(const volatile uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint16_t le16(const volatile uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static int name_matches(const volatile uint8_t *entry, const char *name) {
    unsigned i = 0;
    for (; i < 8 && name[i]; ++i)
        if (entry[i] != (uint8_t)name[i]) return 0;
    if (i == 8) return name[i] == 0;
    for (; i < 8; ++i)
        if (entry[i] != 0) return 0;
    return 1;
}

int doom_find_lump(const volatile uint8_t *wad, uint32_t wad_size,
                   const char *name, doom_lump_t *result) {
    if (!wad || !name || !result || wad_size < 12 ||
        (wad[0] != 'I' && wad[0] != 'P') ||
        wad[1] != 'W' || wad[2] != 'A' || wad[3] != 'D') return -1;
    uint32_t count = le32(wad + 4);
    uint32_t directory = le32(wad + 8);
    if (directory > wad_size || count > (wad_size - directory) / 16u) return -1;
    int found = 0;
    for (uint32_t i = 0; i < count; ++i) {
        const volatile uint8_t *entry = wad + directory + 16u * i;
        uint32_t offset = le32(entry);
        uint32_t length = le32(entry + 4);
        if (length && (offset > wad_size || length > wad_size - offset)) return -1;
        if (name_matches(entry + 8, name)) {
            result->offset = offset;
            result->size = length;
            found = 1;
        }
    }
    return found;
}

int doom_decode_patch(const volatile uint8_t *patch, uint32_t patch_size,
                      uint8_t *pixels, uint16_t width, uint16_t height) {
    if (!patch || !pixels || !width || !height ||
        patch_size < 8u + 4u * width ||
        le16(patch) != width || le16(patch + 2) != height) return 0;
    for (uint32_t i = 0; i < (uint32_t)width * height; ++i) pixels[i] = 0;
    for (uint32_t x = 0; x < width; ++x) {
        uint32_t at = le32(patch + 8u + 4u * x);
        if (at >= patch_size) return 0;
        for (;;) {
            if (at >= patch_size) return 0;
            uint32_t top = patch[at++];
            if (top == 255u) break;
            if (at > patch_size - 2u) return 0;
            uint32_t length = patch[at++];
            ++at; /* unused byte before post data */
            if (length >= patch_size - at) return 0;
            for (uint32_t y = 0; y < length; ++y)
                if (top + y < height)
                    pixels[(top + y) * width + x] = patch[at + y];
            at += length + 1u; /* unused byte after post data */
        }
    }
    return 1;
}
