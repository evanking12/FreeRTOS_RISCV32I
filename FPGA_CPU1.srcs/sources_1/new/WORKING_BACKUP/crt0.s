    .section .start
    .globl _start

/* ======================================================================
 *  RISC-V Reset Startup (crt0.s) for FreeRTOS
 *  - Install early trap handler (CRITICAL - before any code runs!)
 *  - Zero .bss
 *  - Copy .data from flash → RAM (if needed)
 *  - Set up initial stack
 *  - Call main()
 *  - Call vTaskStartScheduler()
 * ====================================================================== */

_start:
    /* ------------------------------------------------------
     * FIRST: Install early trap handler!
     * This catches any ecalls/exceptions before FreeRTOS starts.
     * Without this, mtvec=0 and any trap causes a reset!
     * ------------------------------------------------------ */
    la   t0, _early_trap_handler
    csrw mtvec, t0

    /* ------------------------------------------------------
     * Disable interrupts and reset MTIMECMP
     * This prevents interrupt storms on warm restart!
     * ------------------------------------------------------ */
    li   t0, 0
    csrw mstatus, t0           # Clear mstatus.MIE
    csrw mie, t0               # Clear all interrupt enables
    
    # Reset MTIMECMP to max value (prevents timer interrupts)
    # MTIMECMP_LO = 0xFFFF0010, MTIMECMP_HI = 0xFFFF0014
    li   t0, 0xFFFF0010        # MTIMECMP_LO address
    li   t1, -1                # 0xFFFFFFFF
    sw   t1, 0(t0)             # MTIMECMP_LO = 0xFFFFFFFF
    sw   t1, 4(t0)             # MTIMECMP_HI = 0xFFFFFFFF

    /* ------------------------------------------------------
     * Set up stack pointer
     * ------------------------------------------------------ */
    la   sp, _stack_top

    /* DEBUG: Verify mtvec was set correctly */
    /* Print "[MTVEC=0x" then 8 hex digits then "]\n" to UART */
    li   t1, 0xFFFFFFF0        # UART TX address
    li   t2, 0xFFFFFFF4        # UART status address
    
    # Print "[MTVEC=0x"
    li   t3, '['
    sw   t3, 0(t1)
    li   t3, 'M'
    sw   t3, 0(t1)
    li   t3, 'T'
    sw   t3, 0(t1)
    li   t3, 'V'
    sw   t3, 0(t1)
    li   t3, 'E'
    sw   t3, 0(t1)
    li   t3, 'C'
    sw   t3, 0(t1)
    li   t3, '='
    sw   t3, 0(t1)
    li   t3, '0'
    sw   t3, 0(t1)
    li   t3, 'x'
    sw   t3, 0(t1)
    
    # Read mtvec and print as 8 hex digits
    csrr t0, mtvec
    li   t4, 28               # Start with bits 31:28
_print_mtvec_loop:
    srl  t3, t0, t4           # Shift to get nibble
    andi t3, t3, 0xF          # Mask to 4 bits
    li   t5, 10
    blt  t3, t5, _print_mtvec_digit
    addi t3, t3, 'A' - 10     # Convert A-F
    j    _print_mtvec_out
_print_mtvec_digit:
    addi t3, t3, '0'          # Convert 0-9
_print_mtvec_out:
    sw   t3, 0(t1)            # Print digit
    addi t4, t4, -4           # Next nibble
    bgez t4, _print_mtvec_loop
    
    # Print "]\n"
    li   t3, ']'
    sw   t3, 0(t1)
    li   t3, '\r'
    sw   t3, 0(t1)
    li   t3, '\n'
    sw   t3, 0(t1)

    /* ------------------------------------------------------
     * Clear .bss section
     * ------------------------------------------------------ */
    la   t0, _sbss
    la   t1, _ebss
1:
    bge  t0, t1, 2f
    sw   x0, 0(t0)
    addi t0, t0, 4
    j    1b
2:

    /* ------------------------------------------------------
     * OPTIONAL: if .data is in flash, copy it into RAM  
     * (Your linker currently puts everything in RAM,
     * so this loop does nothing but is future-proof.)
     * ------------------------------------------------------ */
    la   t0, _sidata   /* Source (.text/.rodata) */
    la   t1, _sdata    /* Dest (.data) */
    la   t2, _edata    /* End of .data */
3:
    bge  t1, t2, 4f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    3b
4:

    /* ------------------------------------------------------
     * Call main() — should create tasks
     * (Interrupts already disabled at _start)
     * ------------------------------------------------------ */
    call main

    /* ------------------------------------------------------
     * Start Scheduler (never returns)
     * ------------------------------------------------------ */
    call vTaskStartScheduler

/* ----------------------------------------------------------
 * If scheduler exits — trap forever
 * ---------------------------------------------------------- */
5:  j 5b


/* ==============================================================
 * EARLY TRAP HANDLER
 * Handles any traps that occur BEFORE FreeRTOS scheduler starts.
 * For ecalls: advance mepc and return (makes them no-ops)
 * For interrupts: clear and return
 * For other exceptions: hang (shouldn't happen)
 * 
 * FreeRTOS will overwrite mtvec with its own handler later.
 * ============================================================== */
    .align 4
_early_trap_handler:
    /* Save t0, t1 on stack */
    addi sp, sp, -8
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    
    /* Check mcause */
    csrr t0, mcause
    
    /* If interrupt (bit 31 set), just return */
    srli t1, t0, 31
    bnez t1, _early_trap_return
    
    /* Exception: check if ecall (cause = 11) */
    li   t1, 11
    bne  t0, t1, _early_trap_hang
    
    /* ecall: advance mepc past the instruction and return */
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    
_early_trap_return:
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    addi sp, sp, 8
    mret

_early_trap_hang:
    /* Unexpected exception - hang forever */
    /* (You can add UART debug here if needed) */
    j    _early_trap_hang


/* Symbols provided by linker script */
    .global _sbss
    .global _ebss
    .global _sdata
    .global _edata
    .global _sidata
    .global _stack_top
