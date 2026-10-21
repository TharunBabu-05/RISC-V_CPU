OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { APP (rwx) : ORIGIN = 0x80000000, LENGTH = 1M }
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
    __heap_start = _stack_top;
    __heap_end = 0x81FFF000;
    ASSERT(_image_end <= _stack_top - 16384,
           "DOOM image leaves less than 16 KiB of stack")
    /DISCARD/ : { *(.comment) *(.eh_frame) *(.riscv.attributes) }
}
