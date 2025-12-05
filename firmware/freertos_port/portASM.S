/*
 * FreeRTOS RISC-V Port - Simplified (based on working backup)
 * Key: NO mstatus manipulation in trap_exit
 */

    .section .text
    .globl pxPortInitialiseStack
    .globl xPortStartFirstTask
    .globl freertos_risc_v_trap_handler

    .extern pxCurrentTCB
    .extern vPortSysTickHandler
    .extern vPortYieldHandler

/* ------------------------------------------------------------------------
 * pxPortInitialiseStack - Initialize task stack frame (116 bytes)
 * ------------------------------------------------------------------------ */
pxPortInitialiseStack:
    addi t0, a0, -116           /* Allocate 116 bytes */

    /* mepc (task entry point) at offset 0 */
    sw a1, 0(t0)

    /* ra, t0-t6 - all zero */
    sw x0, 4(t0)
    sw x0, 8(t0)
    sw x0, 12(t0)
    sw x0, 16(t0)
    sw x0, 20(t0)
    sw x0, 24(t0)
    sw x0, 28(t0)
    sw x0, 32(t0)

    /* s0-s11 - all zero */
    sw x0, 36(t0)
    sw x0, 40(t0)
    sw x0, 44(t0)
    sw x0, 48(t0)
    sw x0, 52(t0)
    sw x0, 56(t0)
    sw x0, 60(t0)
    sw x0, 64(t0)
    sw x0, 68(t0)
    sw x0, 72(t0)
    sw x0, 76(t0)
    sw x0, 80(t0)

    /* a0-a7 (a0 = task parameter, rest zero) */
    sw a2, 84(t0)
    sw x0, 88(t0)
    sw x0, 92(t0)
    sw x0, 96(t0)
    sw x0, 100(t0)
    sw x0, 104(t0)
    sw x0, 108(t0)
    sw x0, 112(t0)

    mv a0, t0
    ret


/* ------------------------------------------------------------------------
 * xPortStartFirstTask - Start the first task
 * ------------------------------------------------------------------------ */
xPortStartFirstTask:
    /* Set trap handler */
    la t0, freertos_risc_v_trap_handler
    csrw mtvec, t0

    /* Set MPIE=1, MPP=Machine, MIE=0 (interrupts disabled until mret) */
    /* mret will atomically: MIE <- MPIE, then jump to mepc */
    /* This prevents timer interrupts during register restore! */
    li t1, (1 << 7) | (3 << 11)   /* MPIE=1, MPP=Machine, MIE=0 */
    csrw mstatus, t1

    /* Load first task's TCB and stack pointer */
    la t2, pxCurrentTCB
    lw t2, 0(t2)
    lw sp, 0(t2)

    /* Restore mepc */
    lw t0, 0(sp)
    csrw mepc, t0

    /* Restore all registers */
    lw ra, 4(sp)
    lw t0, 8(sp)
    lw t1, 12(sp)
    lw t2, 16(sp)
    lw t3, 20(sp)
    lw t4, 24(sp)
    lw t5, 28(sp)
    lw t6, 32(sp)
    lw s0, 36(sp)
    lw s1, 40(sp)
    lw s2, 44(sp)
    lw s3, 48(sp)
    lw s4, 52(sp)
    lw s5, 56(sp)
    lw s6, 60(sp)
    lw s7, 64(sp)
    lw s8, 68(sp)
    lw s9, 72(sp)
    lw s10, 76(sp)
    lw s11, 80(sp)
    lw a0, 84(sp)
    lw a1, 88(sp)
    lw a2, 92(sp)
    lw a3, 96(sp)
    lw a4, 100(sp)
    lw a5, 104(sp)
    lw a6, 108(sp)
    lw a7, 112(sp)
    addi sp, sp, 116

    mret


/* ------------------------------------------------------------------------
 * freertos_risc_v_trap_handler - Handle all traps
 * ------------------------------------------------------------------------ */
    .align 4
freertos_risc_v_trap_handler:
    addi sp, sp, -116

    /* Save all registers */
    sw ra, 4(sp)
    sw t0, 8(sp)
    sw t1, 12(sp)
    sw t2, 16(sp)
    sw t3, 20(sp)
    sw t4, 24(sp)
    sw t5, 28(sp)
    sw t6, 32(sp)
    sw s0, 36(sp)
    sw s1, 40(sp)
    sw s2, 44(sp)
    sw s3, 48(sp)
    sw s4, 52(sp)
    sw s5, 56(sp)
    sw s6, 60(sp)
    sw s7, 64(sp)
    sw s8, 68(sp)
    sw s9, 72(sp)
    sw s10, 76(sp)
    sw s11, 80(sp)
    sw a0, 84(sp)
    sw a1, 88(sp)
    sw a2, 92(sp)
    sw a3, 96(sp)
    sw a4, 100(sp)
    sw a5, 104(sp)
    sw a6, 108(sp)
    sw a7, 112(sp)

    /* Save mepc */
    csrr t0, mepc
    sw t0, 0(sp)

    /* Save SP to current TCB */
    la t1, pxCurrentTCB
    lw t2, 0(t1)
    sw sp, 0(t2)

    /* Read mcause */
    csrr t0, mcause

    /* Check interrupt bit (bit 31) */
    srli t1, t0, 31
    bnez t1, handle_interrupt

    /* --- EXCEPTION (ecall) --- */
    /* Advance mepc past ecall instruction */
    lw t1, 0(sp)
    addi t1, t1, 4
    sw t1, 0(sp)

    call vPortYieldHandler
    j trap_exit

handle_interrupt:
    /* Check if timer interrupt (cause = 7) */
    li t2, 7
    li t3, 0x7FFFFFFF
    and t0, t0, t3
    beq t0, t2, handle_timer
    j trap_exit

handle_timer:
    call vPortSysTickHandler

trap_exit:
    /* Load SP from (possibly changed) pxCurrentTCB */
    la t1, pxCurrentTCB
    lw t2, 0(t1)
    lw sp, 0(t2)

    /* Restore mepc */
    lw t0, 0(sp)
    csrw mepc, t0

    /* Set MPIE=1 so mret enables interrupts (MIE = MPIE = 1) */
    /* Also set MPP=Machine mode (bits 12:11 = 3) */
    li t0, (1 << 7) | (3 << 11)   /* MPIE=1, MPP=Machine, MIE=0 */
    csrw mstatus, t0

    /* Restore all registers */
    lw ra, 4(sp)
    lw t0, 8(sp)
    lw t1, 12(sp)
    lw t2, 16(sp)
    lw t3, 20(sp)
    lw t4, 24(sp)
    lw t5, 28(sp)
    lw t6, 32(sp)
    lw s0, 36(sp)
    lw s1, 40(sp)
    lw s2, 44(sp)
    lw s3, 48(sp)
    lw s4, 52(sp)
    lw s5, 56(sp)
    lw s6, 60(sp)
    lw s7, 64(sp)
    lw s8, 68(sp)
    lw s9, 72(sp)
    lw s10, 76(sp)
    lw s11, 80(sp)
    lw a0, 84(sp)
    lw a1, 88(sp)
    lw a2, 92(sp)
    lw a3, 96(sp)
    lw a4, 100(sp)
    lw a5, 104(sp)
    lw a6, 108(sp)
    lw a7, 112(sp)
    addi sp, sp, 116

    /* mret: MIE = MPIE = 1, PC = mepc */
    mret
