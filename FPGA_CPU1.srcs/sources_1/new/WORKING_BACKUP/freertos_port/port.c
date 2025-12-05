/*
 * FreeRTOS RISC-V Port - srv32 Style (Proven Working)
 * Simple approach: C handlers, no ISR stack complexity
 */

#include "FreeRTOS.h"
#include "task.h"
#include <stdint.h>
#include "../uart.h"

/* External assembly functions */
extern void xPortStartFirstTask(void);

/* Critical nesting counter (referenced in portmacro.h) */
size_t xCriticalNesting = 0;

/* Machine CSRs */
#define read_csr(reg) ({ uint32_t v; __asm volatile ("csrr %0, " #reg : "=r"(v)); v; })
#define write_csr(reg, val) __asm volatile ("csrw " #reg ", %0" :: "rK"(val))

/* Memory-mapped timer registers */
#define MTIME_LO     (*(volatile uint32_t *)(configMTIME_BASE_ADDRESS))
#define MTIME_HI     (*(volatile uint32_t *)(configMTIME_BASE_ADDRESS + 4))
#define MTIMECMP_LO  (*(volatile uint32_t *)(configMTIMECMP_BASE_ADDRESS))
#define MTIMECMP_HI  (*(volatile uint32_t *)(configMTIMECMP_BASE_ADDRESS + 4))

/*-----------------------------------------------------------*/

/* Helper to read 64-bit mtime safely */
static inline uint64_t read_mtime(void) {
    uint32_t lo, hi;
    do {
        hi = MTIME_HI;
        lo = MTIME_LO;
    } while (hi != MTIME_HI);
    return ((uint64_t)hi << 32) | lo;
}

/* Helper to write 64-bit mtimecmp safely */
static inline void write_mtimecmp(uint64_t val) {
    MTIMECMP_HI = 0xFFFFFFFF;       /* Prevent spurious interrupt */
    MTIMECMP_LO = (uint32_t)val;
    MTIMECMP_HI = (uint32_t)(val >> 32);
}

/*-----------------------------------------------------------*/

void vPortSetupTimerInterrupt(void)
{
    uart_puts("[PORT] Setting up timer...\r\n");
    
    uint64_t now = read_mtime();
    uint64_t next = now + (configCPU_CLOCK_HZ / configTICK_RATE_HZ);
    write_mtimecmp(next);
    
    uart_puts("[PORT] Timer tick interval: ");
    /* Print as hex */
    uint32_t interval = configCPU_CLOCK_HZ / configTICK_RATE_HZ;
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc("0123456789ABCDEF"[(interval >> i) & 0xF]);
    }
    uart_puts("\r\n");
}

/*-----------------------------------------------------------*/

BaseType_t xPortStartScheduler(void)
{
    uart_puts("\r\n[PORT] >>> xPortStartScheduler (srv32 style) <<<\r\n");
    
    /* Disable all interrupts */
    write_csr(mstatus, 0);
    write_csr(mie, 0);
    
    /* Setup timer */
    vPortSetupTimerInterrupt();
    
    /* Enable ONLY timer interrupt (bit 7) */
    write_csr(mie, (1 << 7));
    uart_puts("[PORT] mie = 0x80 (MTIE only)\r\n");
    
    /* Start first task - sets mtvec, enables interrupts via mret */
    uart_puts("[PORT] Calling xPortStartFirstTask()...\r\n");
    xPortStartFirstTask();

    /* Should never get here */
    uart_puts("[PORT] ERROR: Scheduler returned!\r\n");
    return pdFALSE;
}

/*-----------------------------------------------------------*/

void vPortEndScheduler(void)
{
    for (;;);
}

/*-----------------------------------------------------------*/

/* Timer interrupt handler - called from assembly trap handler */
void vPortSysTickHandler(void)
{
    /* Update timer compare for next tick FIRST (clears interrupt) */
    uint64_t cmp = ((uint64_t)MTIMECMP_HI << 32) | MTIMECMP_LO;
    uint64_t next = cmp + (configCPU_CLOCK_HZ / configTICK_RATE_HZ);
    write_mtimecmp(next);

    /* Run FreeRTOS tick processing */
    if (xTaskIncrementTick() != pdFALSE) {
        vTaskSwitchContext();
    }
}

/*-----------------------------------------------------------*/

/* Yield handler - called from assembly trap handler on ecall */
void vPortYieldHandler(void)
{
    vTaskSwitchContext();
}

/*-----------------------------------------------------------*/

/* FreeRTOS hooks */
void vApplicationIdleHook(void)
{
    /* Idle - do nothing */
}

void vApplicationTickHook(void)
{
    static uint32_t tick_count = 0;
    tick_count++;
    
    /* Print every 1000 ticks (1 second) */
    if ((tick_count % 1000) == 0) {
        uart_puts("[TICK ");
        /* Quick decimal print */
        char buf[12];
        int i = 0;
        uint32_t v = tick_count;
        if (v == 0) buf[i++] = '0';
        else { while (v) { buf[i++] = '0' + (v % 10); v /= 10; } }
        while (i > 0) uart_putc(buf[--i]);
        uart_puts("]\r\n");
    }
}

void vApplicationMallocFailedHook(void)
{
    uart_puts("[PORT] MALLOC FAILED!\r\n");
    for (;;);
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask;
    uart_puts("[PORT] STACK OVERFLOW: ");
    uart_puts(pcTaskName);
    uart_puts("\r\n");
    for (;;);
}
