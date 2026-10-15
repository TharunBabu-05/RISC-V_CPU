/* UART-loaded application memory layout.
 *
 * 0x0000_0000..0x0000_3fff is reserved for the resident bootloader.
 * The uploaded binary starts at 0x0000_4000 and has 48 KiB available,
 * including its code, globals, BSS and downward-growing stack.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    APP (rwx) : ORIGIN = 0x00004000, LENGTH = 48K
}

SECTIONS {
    .text ORIGIN(APP) : {
        KEEP(*(.text.startup))
        KEEP(*(.text.trap))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > APP

    PROVIDE(__global_pointer$ = . + 0x800);

    .data : {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > APP

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > APP

    _image_end = .;
    _stack_top = ORIGIN(APP) + LENGTH(APP);

    ASSERT(_image_end <= _stack_top - 2048,
           "Application leaves less than 2 KiB for its stack")

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.riscv.attributes)
    }
}
