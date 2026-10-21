#ifndef DDR_WAD_HANDOFF_H
#define DDR_WAD_HANDOFF_H

#include <stdint.h>

#define DDR_WAD_HANDOFF_ADDR 0x81FFF000u
#define DDR_WAD_HANDOFF_MAGIC 0x31444157u
#define DDR_WAD_BASE 0x82000000u
#define DDR_WAD_MAX (32u * 1024u * 1024u)

typedef struct {
    uint32_t magic;
    uint32_t base;
    uint32_t size;
    uint32_t crc32;
} ddr_wad_handoff_t;

#endif
