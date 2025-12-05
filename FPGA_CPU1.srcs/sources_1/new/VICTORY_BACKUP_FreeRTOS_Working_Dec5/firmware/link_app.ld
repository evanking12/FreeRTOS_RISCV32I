/* Application Firmware Linker Script - starts at 0x1000 */
/* This firmware is uploaded via UART bootloader */
ENTRY(_start)

MEMORY {
    /* Bootloader occupies 0x0000 - 0x0FFF */
    RAM (rwx) : ORIGIN = 0x00001000, LENGTH = 124K
}

SECTIONS {
    /* Code and read-only data */
    .text : {
        *(.start)
        *(.text*)
        *(.rodata*)
    } > RAM

    /* Initialized data */
    .data : AT (ADDR(.text) + SIZEOF(.text)) {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > RAM
    _sidata = LOADADDR(.data);

    /* Zeroed .bss section */
    .bss : {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > RAM

    . = ALIGN(8);
}

/* Stack grows down from top of RAM */
_stack_top = 0x00020000;

