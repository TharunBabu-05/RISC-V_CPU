#include <stdint.h>
#include "soc.h"
#include "uart.h"

static volatile uint32_t data_word = 0x51a7c0deu;
static volatile uint32_t bss_word;

int main(void) {
    if (data_word != 0x51a7c0deu || bss_word != 0) {
        uart_puts("DDR_APP:FAIL\r\n");
        for (;;) { }
    }
    bss_word = data_word ^ 0xffffffffu;
    if (bss_word != 0xae583f21u) {
        uart_puts("DDR_APP:FAIL\r\n");
        for (;;) { }
    }
    uart_puts("DDR_APP:PASS code/data/BSS from DDR\r\n");
    for (;;) { }
}
