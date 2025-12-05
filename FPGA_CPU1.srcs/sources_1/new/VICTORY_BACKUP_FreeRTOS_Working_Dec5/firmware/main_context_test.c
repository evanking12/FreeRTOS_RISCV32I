/*
 * CONTEXT SWITCH DEBUG TEST
 * =========================
 * Tests context save/restore WITHOUT FreeRTOS.
 * This mimics exactly what FreeRTOS does during a context switch.
 * 
 * Run with: build_debug.sh context_test
 */

#include <stdint.h>
#include <stddef.h>
#include "uart.h"

/* CSR access macros */
#define read_csr(reg) ({ uint32_t v; __asm volatile ("csrr %0, " #reg : "=r"(v)); v; })
#define write_csr(reg, val) __asm volatile ("csrw " #reg ", %0" :: "rK"(val))

/* Timer registers */
#define MTIME_LO        (*(volatile uint32_t *)0xFFFF0008)
#define MTIMECMP_LO     (*(volatile uint32_t *)0xFFFF0010)
#define MTIMECMP_HI     (*(volatile uint32_t *)0xFFFF0014)

/*==========================================================================
 * TASK SIMULATION
 * Simulate two tasks with their own stacks and TCBs
 *=========================================================================*/

/* Stack size for each "task" */
#define TASK_STACK_SIZE 256

/* Task stacks */
uint32_t task1_stack[TASK_STACK_SIZE] __attribute__((aligned(16)));
uint32_t task2_stack[TASK_STACK_SIZE] __attribute__((aligned(16)));

/* TCB: just holds the stack pointer */
typedef struct {
    uint32_t *pxTopOfStack;
    const char *name;
} TCB_t;

/* Two TCBs */
TCB_t task1_tcb;
TCB_t task2_tcb;

/* Current task pointer (like pxCurrentTCB in FreeRTOS) */
TCB_t *pxCurrentTCB = NULL;

/* Counters to track task execution */
volatile uint32_t task1_count = 0;
volatile uint32_t task2_count = 0;
volatile uint32_t switch_count = 0;

/*==========================================================================
 * UART HELPERS
 *=========================================================================*/
static void print_hex(uint32_t val) {
    uart_puts("0x");
    for (int i = 7; i >= 0; i--) {
        int n = (val >> (i * 4)) & 0xF;
        uart_putc(n < 10 ? '0' + n : 'A' + n - 10);
    }
}

static void print_dec(uint32_t val) {
    if (val == 0) { uart_putc('0'); return; }
    char buf[12]; int i = 0;
    while (val > 0) { buf[i++] = '0' + (val % 10); val /= 10; }
    while (i > 0) uart_putc(buf[--i]);
}

/*==========================================================================
 * TASK FUNCTIONS
 *=========================================================================*/
void task1_func(void *param) {
    (void)param;
    uart_puts("\r\n>>> Task 1 started! <<<\r\n");
    
    for (;;) {
        task1_count++;
        if (task1_count <= 5) {
            uart_puts("  [Task1] count=");
            print_dec(task1_count);
            uart_puts(", yielding...\r\n");
        }
        /* Yield to scheduler */
        __asm volatile ("ecall");
    }
}

void task2_func(void *param) {
    (void)param;
    uart_puts("\r\n>>> Task 2 started! <<<\r\n");
    
    for (;;) {
        task2_count++;
        if (task2_count <= 5) {
            uart_puts("  [Task2] count=");
            print_dec(task2_count);
            uart_puts(", yielding...\r\n");
        }
        /* Yield to scheduler */
        __asm volatile ("ecall");
    }
}

/*==========================================================================
 * STACK INITIALIZATION (mirrors srv32's pxPortInitialiseStack)
 * 
 * Stack layout (116 bytes = 29 words, same as srv32):
 *   Offset 0:   mepc (task entry point)
 *   Offset 4:   ra
 *   Offset 8-32: t0-t6
 *   Offset 36-80: s0-s11
 *   Offset 84-112: a0-a7 (a0 = task parameter)
 *=========================================================================*/
uint32_t *init_task_stack(uint32_t *stack_top, void (*task_func)(void*), void *param) {
    /* Allocate 116 bytes (29 words) for context */
    uint32_t *sp = stack_top - 29;
    
    /* Clear everything first */
    for (int i = 0; i < 29; i++) {
        sp[i] = 0;
    }
    
    /* mepc = task entry point (offset 0) */
    sp[0] = (uint32_t)task_func;
    
    /* a0 = task parameter (offset 84/4 = 21) */
    sp[21] = (uint32_t)param;
    
    uart_puts("  Stack initialized:\r\n");
    uart_puts("    stack_top = "); print_hex((uint32_t)stack_top); uart_puts("\r\n");
    uart_puts("    context   = "); print_hex((uint32_t)sp); uart_puts("\r\n");
    uart_puts("    mepc      = "); print_hex(sp[0]); uart_puts("\r\n");
    
    return sp;
}

/*==========================================================================
 * SIMPLE SCHEDULER
 * Called from trap handler to switch tasks
 *=========================================================================*/
void vTaskSwitchContext(void) {
    switch_count++;
    
    /* Round-robin between task1 and task2 */
    if (pxCurrentTCB == &task1_tcb) {
        pxCurrentTCB = &task2_tcb;
    } else {
        pxCurrentTCB = &task1_tcb;
    }
    
    if (switch_count <= 10) {
        uart_puts("  [SWITCH] -> ");
        uart_puts(pxCurrentTCB->name);
        uart_puts(" (sp=");
        print_hex((uint32_t)pxCurrentTCB->pxTopOfStack);
        uart_puts(")\r\n");
    }
}

/*==========================================================================
 * CONTEXT SWITCH TRAP HANDLER (mirrors srv32's freertos_risc_v_trap_handler)
 *=========================================================================*/
__attribute__((naked, aligned(4)))
void context_switch_handler(void) {
    __asm volatile (
        /* Allocate 116-byte context frame */
        "addi sp, sp, -116           \n"
        
        /* Save all registers (same order as srv32) */
        "sw ra, 4(sp)                \n"
        "sw t0, 8(sp)                \n"
        "sw t1, 12(sp)               \n"
        "sw t2, 16(sp)               \n"
        "sw t3, 20(sp)               \n"
        "sw t4, 24(sp)               \n"
        "sw t5, 28(sp)               \n"
        "sw t6, 32(sp)               \n"
        "sw s0, 36(sp)               \n"
        "sw s1, 40(sp)               \n"
        "sw s2, 44(sp)               \n"
        "sw s3, 48(sp)               \n"
        "sw s4, 52(sp)               \n"
        "sw s5, 56(sp)               \n"
        "sw s6, 60(sp)               \n"
        "sw s7, 64(sp)               \n"
        "sw s8, 68(sp)               \n"
        "sw s9, 72(sp)               \n"
        "sw s10, 76(sp)              \n"
        "sw s11, 80(sp)              \n"
        "sw a0, 84(sp)               \n"
        "sw a1, 88(sp)               \n"
        "sw a2, 92(sp)               \n"
        "sw a3, 96(sp)               \n"
        "sw a4, 100(sp)              \n"
        "sw a5, 104(sp)              \n"
        "sw a6, 108(sp)              \n"
        "sw a7, 112(sp)              \n"
        
        /* Save mepc at offset 0 */
        "csrr t0, mepc               \n"
        "addi t0, t0, 4              \n"  /* Advance past ecall */
        "sw t0, 0(sp)                \n"
        
        /* Save SP to current TCB */
        "la t1, pxCurrentTCB         \n"
        "lw t2, 0(t1)                \n"  /* t2 = pxCurrentTCB */
        "sw sp, 0(t2)                \n"  /* pxCurrentTCB->pxTopOfStack = sp */
        
        /* Call scheduler to switch tasks */
        "call vTaskSwitchContext     \n"
        
        /* Load SP from (possibly new) TCB */
        "la t1, pxCurrentTCB         \n"
        "lw t2, 0(t1)                \n"  /* t2 = pxCurrentTCB */
        "lw sp, 0(t2)                \n"  /* sp = pxCurrentTCB->pxTopOfStack */
        
        /* Restore mepc */
        "lw t0, 0(sp)                \n"
        "csrw mepc, t0               \n"
        
        /* Restore all registers */
        "lw ra, 4(sp)                \n"
        "lw t0, 8(sp)                \n"
        "lw t1, 12(sp)               \n"
        "lw t2, 16(sp)               \n"
        "lw t3, 20(sp)               \n"
        "lw t4, 24(sp)               \n"
        "lw t5, 28(sp)               \n"
        "lw t6, 32(sp)               \n"
        "lw s0, 36(sp)               \n"
        "lw s1, 40(sp)               \n"
        "lw s2, 44(sp)               \n"
        "lw s3, 48(sp)               \n"
        "lw s4, 52(sp)               \n"
        "lw s5, 56(sp)               \n"
        "lw s6, 60(sp)               \n"
        "lw s7, 64(sp)               \n"
        "lw s8, 68(sp)               \n"
        "lw s9, 72(sp)               \n"
        "lw s10, 76(sp)              \n"
        "lw s11, 80(sp)              \n"
        "lw a0, 84(sp)               \n"
        "lw a1, 88(sp)               \n"
        "lw a2, 92(sp)               \n"
        "lw a3, 96(sp)               \n"
        "lw a4, 100(sp)              \n"
        "lw a5, 104(sp)              \n"
        "lw a6, 108(sp)              \n"
        "lw a7, 112(sp)              \n"
        
        /* Deallocate context frame */
        "addi sp, sp, 116            \n"
        
        "mret                        \n"
    );
}

/*==========================================================================
 * START FIRST TASK (mirrors srv32's xPortStartFirstTask)
 *=========================================================================*/
__attribute__((naked))
void start_first_task(void) {
    __asm volatile (
        /* Set trap handler */
        "la t0, context_switch_handler \n"
        "csrw mtvec, t0              \n"
        
        /* Load first task's SP from TCB */
        "la t2, pxCurrentTCB         \n"
        "lw t2, 0(t2)                \n"  /* t2 = pxCurrentTCB */
        "lw sp, 0(t2)                \n"  /* sp = pxCurrentTCB->pxTopOfStack */
        
        /* Restore mepc (task entry point) */
        "lw t0, 0(sp)                \n"
        "csrw mepc, t0               \n"
        
        /* Restore all registers */
        "lw ra, 4(sp)                \n"
        "lw t0, 8(sp)                \n"
        "lw t1, 12(sp)               \n"
        "lw t2, 16(sp)               \n"
        "lw t3, 20(sp)               \n"
        "lw t4, 24(sp)               \n"
        "lw t5, 28(sp)               \n"
        "lw t6, 32(sp)               \n"
        "lw s0, 36(sp)               \n"
        "lw s1, 40(sp)               \n"
        "lw s2, 44(sp)               \n"
        "lw s3, 48(sp)               \n"
        "lw s4, 52(sp)               \n"
        "lw s5, 56(sp)               \n"
        "lw s6, 60(sp)               \n"
        "lw s7, 64(sp)               \n"
        "lw s8, 68(sp)               \n"
        "lw s9, 72(sp)               \n"
        "lw s10, 76(sp)              \n"
        "lw s11, 80(sp)              \n"
        "lw a0, 84(sp)               \n"
        "lw a1, 88(sp)               \n"
        "lw a2, 92(sp)               \n"
        "lw a3, 96(sp)               \n"
        "lw a4, 100(sp)              \n"
        "lw a5, 104(sp)              \n"
        "lw a6, 108(sp)              \n"
        "lw a7, 112(sp)              \n"
        
        /* Deallocate context frame */
        "addi sp, sp, 116            \n"
        
        /* Set mstatus for mret: MPIE=1, MPP=Machine */
        "li t0, 0x1880               \n"
        "csrw mstatus, t0            \n"
        
        /* Jump to task! */
        "mret                        \n"
    );
}

/*==========================================================================
 * MAIN TEST RUNNER
 *=========================================================================*/
int main(void) {
    uart_puts("\r\n");
    uart_puts("================================================\r\n");
    uart_puts("   CONTEXT SWITCH DEBUG TEST\r\n");
    uart_puts("================================================\r\n");
    uart_puts("This tests manual context switching WITHOUT FreeRTOS.\r\n");
    uart_puts("If this works, FreeRTOS port should work too.\r\n");
    uart_puts("================================================\r\n");
    
    /* Disable interrupts */
    write_csr(mstatus, 0);
    write_csr(mie, 0);
    MTIMECMP_LO = 0xFFFFFFFF;
    MTIMECMP_HI = 0xFFFFFFFF;
    
    uart_puts("\r\n--- Setting up tasks ---\r\n");
    
    /* Initialize task 1 */
    uart_puts("\r\nInitializing Task 1:\r\n");
    task1_tcb.name = "Task1";
    task1_tcb.pxTopOfStack = init_task_stack(
        &task1_stack[TASK_STACK_SIZE],  /* Top of stack */
        task1_func,
        NULL
    );
    
    /* Initialize task 2 */
    uart_puts("\r\nInitializing Task 2:\r\n");
    task2_tcb.name = "Task2";
    task2_tcb.pxTopOfStack = init_task_stack(
        &task2_stack[TASK_STACK_SIZE],  /* Top of stack */
        task2_func,
        NULL
    );
    
    /* Set current task to task 1 */
    pxCurrentTCB = &task1_tcb;
    
    uart_puts("\r\n--- Starting first task ---\r\n");
    uart_puts("pxCurrentTCB = "); print_hex((uint32_t)pxCurrentTCB); uart_puts("\r\n");
    uart_puts("pxTopOfStack = "); print_hex((uint32_t)pxCurrentTCB->pxTopOfStack); uart_puts("\r\n");
    uart_puts("\r\nCalling start_first_task()...\r\n");
    
    /* This should never return - starts task1 */
    start_first_task();
    
    /* Should never reach here */
    uart_puts("\r\n!!! ERROR: start_first_task returned !!!\r\n");
    for (;;);
}

/* Required by linker */
void vTaskStartScheduler(void) {
    /* Not used in this test */
    for (;;);
}

