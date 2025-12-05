/*
 * FreeRTOS Demo on Custom RISC-V CPU
 * ===================================
 * Two tasks demonstrating cooperative multitasking
 */

#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "uart.h"

/* Task handles */
TaskHandle_t xHeartbeatHandle = NULL;
TaskHandle_t xCounterHandle   = NULL;

/* Print a number as decimal (simple inline version) */
static void print_number(uint32_t val) {
    if (val == 0) {
        uart_putc('0');
        return;
    }
    char buf[12];
    int i = 0;
    while (val > 0 && i < 11) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

/*-----------------------------------------------------------*/

/* Heartbeat Task - prints <3 with count */
void vHeartbeatTask(void *pvParameters) {
    (void)pvParameters;
    
    uint32_t count = 0;

    for (;;) {
        /* Critical section: print entire message atomically */
        taskENTER_CRITICAL();
        uart_puts("<3 #");
        print_number(count++);
        uart_puts("\r\n");
        taskEXIT_CRITICAL();

        /* Small busy-wait then yield */
        for (volatile uint32_t d = 0; d < 50000; d++);
        taskYIELD();
    }
}

/* Counter Task - counts continuously */
void vCounterTask(void *pvParameters) {
    (void)pvParameters;
    
    uint32_t count = 0;
    
    for (;;) {
        /* Critical section: print entire message atomically */
        taskENTER_CRITICAL();
        uart_puts(">> ");
        print_number(count++);
        uart_puts("\r\n");
        taskEXIT_CRITICAL();

        /* Yield after each print */
        taskYIELD();
    }
}

/*-----------------------------------------------------------*/

int main(void) {
    /* Print banner */
    uart_puts("\r\n\r\n");
    uart_puts("================================\r\n");
    uart_puts("  FreeRTOS on Custom RISC-V\r\n");
    uart_puts("================================\r\n");
    uart_puts("Tasks: <3=Heartbeat  >>=Counter\r\n");
    uart_puts("\r\n");
    
    /* Create tasks - SAME priority for round-robin */
    uart_puts("Creating tasks...\r\n");
    
    BaseType_t ret1 = xTaskCreate(vHeartbeatTask, "HB", 512, NULL, 1, &xHeartbeatHandle);
    BaseType_t ret2 = xTaskCreate(vCounterTask, "CNT", 512, NULL, 1, &xCounterHandle);
    
    if (ret1 == pdPASS && ret2 == pdPASS) {
        uart_puts("Tasks created OK\r\n");
    } else {
        uart_puts("Task creation FAILED!\r\n");
    }
    
    uart_puts("Starting scheduler...\r\n\r\n");
    
    /* Start FreeRTOS scheduler - never returns */
    vTaskStartScheduler();
    
    /* Should never reach here */
    uart_puts("!!! Scheduler returned !!!\r\n");
    for (;;);
}
