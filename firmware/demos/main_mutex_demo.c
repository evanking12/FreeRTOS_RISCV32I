/*
 * FreeRTOS Mutex Demo - Custom RISC-V CPU
 * Demonstrates mutex for shared resource protection
 * 
 * Two tasks compete for UART access using a mutex.
 * Without the mutex, output would be garbled.
 */

#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "uart.h"

/* Mutex handle for UART protection */
static SemaphoreHandle_t xUartMutex = NULL;

/* Counters */
static volatile uint32_t countA = 0;
static volatile uint32_t countB = 0;

/* Print number helper */
static void print_num(uint32_t val) {
    char buf[12];
    int i = 0;
    if (val == 0) { uart_putc('0'); return; }
    while (val > 0 && i < 10) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    while (i > 0) uart_putc(buf[--i]);
}

/* Delay */
static void delay(volatile uint32_t n) {
    while (n--) __asm volatile("nop");
}

/*-----------------------------------------------------------*/

void vTaskA(void *p) {
    (void)p;
    for (;;) {
        /* Take mutex - blocks until available */
        if (xSemaphoreTake(xUartMutex, portMAX_DELAY) == pdTRUE) {
            uart_puts("[A] Mutex acquired! Count: ");
            print_num(countA++);
            uart_puts("\r\n");
            
            /* Release mutex */
            xSemaphoreGive(xUartMutex);
        }
        delay(50000);
        taskYIELD();
    }
}

void vTaskB(void *p) {
    (void)p;
    for (;;) {
        /* Take mutex - blocks until available */
        if (xSemaphoreTake(xUartMutex, portMAX_DELAY) == pdTRUE) {
            uart_puts("[B] Mutex acquired! Count: ");
            print_num(countB++);
            uart_puts("\r\n");
            
            /* Release mutex */
            xSemaphoreGive(xUartMutex);
        }
        delay(50000);
        taskYIELD();
    }
}

/*-----------------------------------------------------------*/

int main(void) {
    uart_puts("\r\n");
    uart_puts("================================\r\n");
    uart_puts("  FreeRTOS MUTEX Demo\r\n");
    uart_puts("  Custom RISC-V CPU\r\n");
    uart_puts("================================\r\n\r\n");
    
    /* Create mutex for UART protection */
    xUartMutex = xSemaphoreCreateMutex();
    
    if (xUartMutex != NULL) {
        uart_puts("[OK] Mutex created!\r\n\r\n");
        
        /* Create tasks */
        xTaskCreate(vTaskA, "A", 256, NULL, 1, NULL);
        xTaskCreate(vTaskB, "B", 256, NULL, 1, NULL);
        
        /* Start scheduler */
        vTaskStartScheduler();
    } else {
        uart_puts("[FAIL] Mutex creation failed!\r\n");
    }
    
    for (;;);
}

