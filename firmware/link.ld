ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 128K
}

SECTIONS {
    /* --- Code and read-only data --- */
    .text : {
        *(.start)
        *(.text*)
    } > RAM

    /* --- Small read-only data --- */
    .srodata : {
        *(.srodata*)
    } > RAM

    /* --- Read-only data --- */
    .rodata : {
        *(.rodata*)
    } > RAM

    /* --- Small initialized data (.sdata) --- */
    .sdata : {
        __global_pointer$ = . + 0x800;
        *(.sdata*)
    } > RAM

    /* --- Initialized data (.data) --- */
    .data : {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > RAM
    _sidata = LOADADDR(.data);

    /* --- Zeroed .bss section --- */
    .bss : {
        _sbss = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > RAM

    /* Align end of RAM before reserving stack */
    . = ALIGN(16);
    
    /* Heap starts after bss */
    _heap_start = .;
}

/* Stack grows down from the top of RAM */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);
