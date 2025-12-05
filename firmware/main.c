/*
 * FreeRTOS Demo - Custom RISC-V CPU (Stable Demo Version)
 * Simple and reliable for live demos
 */

#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "uart.h"

/* Global counters - avoids any stack weirdness */
static volatile uint32_t countA = 0;
static volatile uint32_t countB = 0;
static volatile uint32_t countC = 0;

/* Print decimal number */
static void print_num(uint32_t val) {
    char buf[12];
    int i = 0;
    if (val == 0) { 
        uart_putc('0'); 
        return; 
    }
    while (val > 0 && i < 10) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

/* Delay loop */
static void delay(volatile uint32_t n) {
    while (n--) { __asm volatile("nop"); }
}

/* ─────────────────────────────────────────────────────────────────────────── */

void vTaskA(void *p) {
    (void)p;
    for (;;) {
        taskENTER_CRITICAL();
        uart_puts("[A] ");
        print_num(countA++);
        uart_puts("\r\n");
        taskEXIT_CRITICAL();
        delay(60000);
        taskYIELD();
    }
}

void vTaskB(void *p) {
    (void)p;
    for (;;) {
        taskENTER_CRITICAL();
        uart_puts("[B] ");
        print_num(countB++);
        uart_puts("\r\n");
        taskEXIT_CRITICAL();
        delay(60000);
        taskYIELD();
    }
}

void vTaskC(void *p) {
    (void)p;
    for (;;) {
        taskENTER_CRITICAL();
        uart_puts("[C] ");
        print_num(countC++);
        uart_puts("\r\n");
        taskEXIT_CRITICAL();
        delay(60000);
        taskYIELD();
    }
}

/* ─────────────────────────────────────────────────────────────────────────── */

int main(void) {
    uart_puts("\r\n\r\n");
    uart_puts("========================================\r\n");
    uart_puts("  FreeRTOS on Custom RISC-V CPU\r\n");
    uart_puts("========================================\r\n");
    uart_puts("  CPU:  3-stage pipeline @ 25MHz\r\n");
    uart_puts("  ISA:  RISC-V RV32I\r\n");
    uart_puts("  RTOS: FreeRTOS v10.5.1\r\n");
    uart_puts("========================================\r\n\r\n");
    
    uart_puts("Starting 3 tasks...\r\n\r\n");
    
    xTaskCreate(vTaskA, "A", 256, NULL, 1, NULL);
    xTaskCreate(vTaskB, "B", 256, NULL, 1, NULL);
    xTaskCreate(vTaskC, "C", 256, NULL, 1, NULL);
    
    vTaskStartScheduler();
    
    for (;;);
}
