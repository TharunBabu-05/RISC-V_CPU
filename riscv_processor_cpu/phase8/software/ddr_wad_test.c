#include <stdint.h>
#include "uart.h"

#define WAD ((volatile uint8_t *)0x82000000u)

int main(void) {
    if (WAD[0] != 'P' || WAD[1] != 'W' || WAD[2] != 'A' || WAD[3] != 'D' ||
        WAD[4] != 1 || WAD[8] != 16 ||
        WAD[12] != 'R' || WAD[13] != 'V' ||
        WAD[14] != '3' || WAD[15] != '2' ||
        WAD[16] != 12 || WAD[20] != 4 ||
        WAD[24] != 'H' || WAD[25] != 'E') {
        uart_puts("WAD_APP:FAIL\r\n");
        for (;;) { }
    }
    uart_puts("WAD_APP:PASS DDR lump read\r\n");
    for (;;) { }
}
