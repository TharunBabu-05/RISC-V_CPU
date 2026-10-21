#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "doom_wad_art.h"
#include "ddr_wad_handoff.h"

int main(int argc, char **argv) {
    uint8_t patch[] = {
        2,0,2,0,0,0,0,0, 16,0,0,0,23,0,0,0,
        0,2,0,10,20,0,255, 0,2,0,30,40,0,255
    };
    uint8_t pixels[4] = {0};
    assert(doom_decode_patch(patch, sizeof(patch), pixels, 2, 2));
    assert(pixels[0] == 10 && pixels[1] == 30 &&
           pixels[2] == 20 && pixels[3] == 40);
    patch[8] = 30;
    assert(!doom_decode_patch(patch, sizeof(patch), pixels, 2, 2));

    if (argc == 2) {
        FILE *file = fopen(argv[1], "rb");
        assert(file && fseek(file, 0, SEEK_END) == 0);
        long length = ftell(file);
        assert(length > 0 && (unsigned long)length <= DDR_WAD_MAX);
        rewind(file);
        uint8_t *wad = malloc((size_t)length);
        assert(wad && fread(wad, 1, (size_t)length, file) == (size_t)length);
        fclose(file);
        doom_lump_t palette, title;
        assert(doom_find_lump(wad, (uint32_t)length, "PLAYPAL", &palette) == 1);
        assert(palette.size >= 768);
        assert(doom_find_lump(wad, (uint32_t)length, "TITLEPIC", &title) == 1);
        uint8_t *frame = malloc(320u * 200u);
        assert(frame && doom_decode_patch(wad + title.offset, title.size,
                                           frame, 320, 200));
        unsigned distinct = 0;
        uint8_t seen[256] = {0};
        for (unsigned i = 0; i < 320u * 200u; ++i)
            if (!seen[frame[i]]) { seen[frame[i]] = 1; ++distinct; }
        assert(distinct > 16);
        printf("TITLEPIC host decode: 320x200, %u palette indices\n", distinct);
        free(frame);
        free(wad);
    }
    puts("doom_wad_art_test: PASS");
    return 0;
}
