/* First MiB of DDR: small test app now, larger freestanding apps later. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 1M }
SECTIONS {
    .text ORIGIN(DDR) : {
        KEEP(*(.text.startup))
        KEEP(*(.text.trap))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > DDR
    PROVIDE(__global_pointer$ = . + 0x800);
    .data : {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > DDR
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DDR
    _image_end = .;
    _stack_top = ORIGIN(DDR) + LENGTH(DDR);
    ASSERT(_image_end <= _stack_top - 4096,
           "DDR application leaves less than 4 KiB for its stack")
    /DISCARD/ : { *(.comment) *(.eh_frame) *(.riscv.attributes) }
}
