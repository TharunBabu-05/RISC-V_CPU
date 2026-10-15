/* Resident UART bootloader memory layout.
 *
 * The loader occupies the first 16 KiB of BRAM. Applications are linked
 * separately at 0x0000_4000 and may use the remaining 48 KiB.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    BOOT (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS {
    .text ORIGIN(BOOT) : {
        KEEP(*(.text.startup))
        KEEP(*(.text.trap))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > BOOT

    PROVIDE(__global_pointer$ = . + 0x800);

    .data : {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > BOOT

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > BOOT

    _image_end = .;
    _stack_top = ORIGIN(BOOT) + LENGTH(BOOT);

    ASSERT(_image_end <= _stack_top - 1024,
           "Bootloader exceeds its 16 KiB region or leaves less than 1 KiB stack")

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.riscv.attributes)
    }
}
