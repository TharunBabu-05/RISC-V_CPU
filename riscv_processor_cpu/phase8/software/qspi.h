#ifndef QSPI_H
#define QSPI_H

#include <stdint.h>

uint8_t qspi_read_byte(uint32_t flash_address);
uint32_t qspi_read_u32_le(uint32_t flash_address);

#endif /* QSPI_H */
