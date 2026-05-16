/* ============================================================
 *  startup.S  —  RISC-V Bare-Metal Startup Code
 *
 *  This is the very first code that runs when the CPU resets.
 *  It runs before main() and sets up the C runtime environment:
 *    1. Set stack pointer (sp) to top of BRAM data region
 *    2. Zero out the BSS segment (uninitialized global vars)
 *    3. Copy .data section from ROM to RAM if needed
 *    4. Call main()
 *    5. Trap infinite loop if main() ever returns
 *
 *  Memory layout (defined in link.ld):
 *    0x0000_0000 - 0x0000_FFFF  : BRAM (64KB total)
 *    0x0000_0000 - 0x0000_BFFF  : .text + .rodata (48KB for code)
 *    0x0000_C000 - 0x0000_FFFF  : .data + .bss + stack (16KB for data)
 * ============================================================ */

    .section .text.startup, "ax"
    .global _start
    .global _halt

_start:
    /* ---- Step 1: Disable all interrupts ---- */
    csrw    mie,   zero        /* Clear machine interrupt enable */
    csrw    mstatus, zero      /* Disable global interrupts */

    /* ---- Step 2: Set stack pointer ---- */
    /* Stack grows downward from the top of BRAM (0x0001_0000) */
    la      sp, _stack_top

    /* ---- Step 3: Zero the BSS section ---- */
    /* BSS contains uninitialized global/static variables */
    la      a0, _bss_start
    la      a1, _bss_end
bss_clear:
    bge     a0, a1, bss_done
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       bss_clear
bss_done:

    /* ---- Step 4: Call main() ---- */
    call    main

    /* ---- Step 5: Halt if main returns ---- */
_halt:
    j       _halt


/* ============================================================
 *  Minimal trap vector (handles unexpected exceptions)
 *  Simply halts on any trap — for debugging.
 * ============================================================ */
    .section .text.trap, "ax"
    .global _trap_handler
    .align  4                   /* Traps must be 4-byte aligned */
_trap_handler:
    j       _halt               /* Halt on any exception */
