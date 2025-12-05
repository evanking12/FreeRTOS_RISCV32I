/*
 * FreeRTOS Demo on Custom RISC-V CPU
 * Using official FreeRTOS port
 */

#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "uart.h"

/* Task handles */
TaskHandle_t xHeartbeatHandle = NULL;
TaskHandle_t xCounterHandle   = NULL;

/* Shared counter */
volatile uint32_t g_counter = 0;

/* CSR helpers */
static inline uint32_t csr_read_mstatus(void)  { uint32_t v; asm volatile ("csrr %0, mstatus"  : "=r"(v)); return v; }
static inline uint32_t csr_read_mie(void)      { uint32_t v; asm volatile ("csrr %0, mie"      : "=r"(v)); return v; }
static inline uint32_t csr_read_mip(void)      { uint32_t v; asm volatile ("csrr %0, mip"      : "=r"(v)); return v; }
static inline uint32_t csr_read_mtvec(void)    { uint32_t v; asm volatile ("csrr %0, mtvec"    : "=r"(v)); return v; }

/* UART helpers */
static void uart_print_dec(uint32_t val) {
    if (val == 0) { uart_putc('0'); return; }
    char buf[12]; int i = 0;
    while (val > 0) { buf[i++] = (char)('0' + (val % 10)); val /= 10; }
    while (i > 0) { uart_putc(buf[--i]); }
}

/* uart_print_hex is now in uart.c */

/* Timer addresses */
#define MTIME_LO        (*(volatile uint32_t *)0xFFFF0008)
#define MTIME_HI        (*(volatile uint32_t *)0xFFFF000C)

static uint32_t read_mtime(void) {
    return MTIME_LO;
}

/*-----------------------------------------------------------*/

/* Heartbeat Task - prints every second */
void vHeartbeatTask(void *pvParameters) {
    (void)pvParameters;
    
    uart_puts("\r\n>>> Heartbeat task started! <<<\r\n");
    
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xFrequency = pdMS_TO_TICKS(1000);
    uint32_t count = 0;

    for (;;) {
        TickType_t ticks = xTaskGetTickCount();
        uint32_t seconds = ticks / configTICK_RATE_HZ;

        uart_puts("[");
        uart_print_dec(seconds);
        uart_puts("s] Heartbeat #");
        uart_print_dec(count++);
        uart_puts(" (ticks=");
        uart_print_dec(ticks);
        uart_puts(")\r\n");

        vTaskDelayUntil(&xLastWakeTime, xFrequency);
    }
}

/* Counter Task - prints every 2 seconds */
void vCounterTask(void *pvParameters) {
    (void)pvParameters;
    
    uart_puts("\r\n>>> Counter task started! <<<\r\n");
    
    const TickType_t xFrequency = pdMS_TO_TICKS(2000);

    for (;;) {
        TickType_t ticks = xTaskGetTickCount();
        uint32_t seconds = ticks / configTICK_RATE_HZ;

        uart_puts("[");
        uart_print_dec(seconds);
        uart_puts("s] Counter = ");
        uart_print_dec(g_counter++);
        uart_puts("\r\n");

        vTaskDelay(xFrequency);
    }
}

/*-----------------------------------------------------------*/

/* Print system banner */
static void print_banner(void) {
    uart_puts("\r\n\r\n");
    uart_puts("================================================\r\n");
    uart_puts("   RISC-V FreeRTOS - Official Port Test\r\n");
    uart_puts("================================================\r\n");
    uart_puts("CPU:   Custom RV32I @ 25MHz\r\n");
    uart_puts("RTOS:  FreeRTOS v10.5.1 (official port)\r\n");
    uart_puts("Heap:  ");
    uart_print_dec(configTOTAL_HEAP_SIZE);
    uart_puts(" bytes\r\n");
    uart_puts("================================================\r\n\r\n");
}

/* Print CSR state */
static void print_csr_state(const char *label) {
    uart_puts(label);
    uart_puts(": mstatus=0x");
    uart_print_hex(csr_read_mstatus());
    uart_puts(" mie=0x");
    uart_print_hex(csr_read_mie());
    uart_puts(" mtvec=0x");
    uart_print_hex(csr_read_mtvec());
    uart_puts("\r\n");
}

/*-----------------------------------------------------------*/

int main(void) {
    /* Print banner */
    print_banner();
    
    /* Show initial CSR state */
    print_csr_state("[INIT] CSRs");
    
    /* Test timer is running */
    uart_puts("[INIT] MTIME = ");
    uart_print_dec(read_mtime());
    uart_puts("\r\n");
    
    /* Check heap */
    uart_puts("[INIT] Free heap = ");
    uart_print_dec((uint32_t)xPortGetFreeHeapSize());
    uart_puts(" bytes\r\n");
    
    /* Create tasks */
    uart_puts("\r\n[INIT] Creating tasks...\r\n");
    
    BaseType_t ret;
    
    ret = xTaskCreate(vHeartbeatTask, "Heartbeat", 512, NULL, 2, &xHeartbeatHandle);
    uart_puts("  Heartbeat: ");
    uart_puts(ret == pdPASS ? "OK" : "FAIL");
    uart_puts("\r\n");
    
    ret = xTaskCreate(vCounterTask, "Counter", 512, NULL, 1, &xCounterHandle);
    uart_puts("  Counter: ");
    uart_puts(ret == pdPASS ? "OK" : "FAIL");
    uart_puts("\r\n");
    
    /* Show CSRs before scheduler */
    print_csr_state("[INIT] Before scheduler");
    
    uart_puts("\r\n[INIT] Free heap = ");
    uart_print_dec((uint32_t)xPortGetFreeHeapSize());
    uart_puts(" bytes\r\n");
    
    /* Start scheduler */
    uart_puts("\r\n");
    uart_puts("================================================\r\n");
    uart_puts("   Starting FreeRTOS scheduler...\r\n");
    uart_puts("================================================\r\n\r\n");
    
    vTaskStartScheduler();
    
    /* Should never reach here */
    uart_puts("\r\n!!! ERROR: Scheduler returned !!!\r\n");
    for (;;);
}
