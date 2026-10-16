#include "qspi.h"
#include "soc.h"

uint8_t qspi_read_byte(uint32_t flash_address)
{
    QSPI_ADDRESS = flash_address;
    QSPI_CONTROL = QSPI_CONTROL_START;
    while (QSPI_STATUS & QSPI_STATUS_BUSY) { }
    return (uint8_t)QSPI_DATA;
}

uint32_t qspi_read_u32_le(uint32_t flash_address)
{
    uint32_t value = 0;
    value |= (uint32_t)qspi_read_byte(flash_address);
    value |= (uint32_t)qspi_read_byte(flash_address + 1U) << 8;
    value |= (uint32_t)qspi_read_byte(flash_address + 2U) << 16;
    value |= (uint32_t)qspi_read_byte(flash_address + 3U) << 24;
    return value;
}
