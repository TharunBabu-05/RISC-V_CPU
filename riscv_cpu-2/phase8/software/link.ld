/* ============================================================
 *  link.ld  —  Linker Script for RV32 Bare-Metal SoC
 *
 *  Memory Map:
 *    BRAM: 0x0000_0000 – 0x0000_FFFF  (64 KB total)
 *      .text   : 0x0000_0000 (code + rodata, 48 KB max)
 *      .data   : 0x0000_C000 (initialized globals)
 *      .bss    : after .data (zero-initialized globals)
 *      .stack  : 0x0000_FFFC (grows downward, 4KB reserved)
 *
 *  Data BRAM: 0x2000_0000 – 0x2000_FFFF  (64 KB)
 *    (Used for heap / large arrays if needed)
 * ============================================================ */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    BRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS {

    /* ---- Code and Read-Only Data ---- */
    .text 0x00000000 : {
        KEEP(*(.text.startup))  /* _start must be FIRST instruction */
        KEEP(*(.text.trap))     /* Trap handler near the start */
        *(.text .text.*)        /* All other code */
        *(.rodata .rodata.*)    /* String literals, const tables */
        . = ALIGN(4);
    } > BRAM

    /* ---- Initialized Global/Static Variables ---- */
    .data : {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > BRAM

    /* ---- Zero-Initialized (BSS) Variables ---- */
    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > BRAM

    /* ---- Stack (top of BRAM, grows downward) ---- */
    .stack : {
        . = ALIGN(16);
        _stack_bottom = .;
        . = ORIGIN(BRAM) + LENGTH(BRAM) - 4;
        _stack_top = .;
    } > BRAM

    /* ---- Discard debug info for FPGA builds ---- */
    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.riscv.attributes)
    }
}
