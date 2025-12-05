/* Bootloader Linker Script - starts at 0x0 */
ENTRY(_boot_start)

MEMORY {
    BOOT (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM  (rwx) : ORIGIN = 0x00001000, LENGTH = 124K
}

SECTIONS {
    .boot : {
        *(.boot)
    } > BOOT

    .rodata : {
        *(.rodata*)
    } > BOOT

    /* Stack at top of RAM */
    _stack_top = 0x00020000;
}

