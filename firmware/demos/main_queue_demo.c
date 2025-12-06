/*
 * FreeRTOS Queue Demo - Custom RISC-V CPU
 * Demonstrates inter-task communication using queues
 * 
 * Producer task sends numbers to a queue.
 * Consumer task receives and prints them.
 */

#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "uart.h"

/* Queue handle */
static QueueHandle_t xDataQueue = NULL;

/* Message structure */
typedef struct {
    uint32_t value;
    char     source;
} Message_t;

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

/* Producer Task - sends data to queue */
void vProducerTask(void *p) {
    (void)p;
    Message_t msg;
    uint32_t count = 0;
    
    for (;;) {
        msg.value = count++;
        msg.source = 'P';
        
        /* Send to queue (blocks if full) */
        if (xQueueSend(xDataQueue, &msg, portMAX_DELAY) == pdTRUE) {
            /* Successfully sent */
        }
        
        delay(80000);
    }
}

/* Consumer Task - receives data from queue */
void vConsumerTask(void *p) {
    (void)p;
    Message_t msg;
    
    for (;;) {
        /* Receive from queue (blocks if empty) */
        if (xQueueReceive(xDataQueue, &msg, portMAX_DELAY) == pdTRUE) {
            uart_puts("[Consumer] Received from ");
            uart_putc(msg.source);
            uart_puts(": ");
            print_num(msg.value);
            uart_puts("\r\n");
        }
    }
}

/*-----------------------------------------------------------*/

int main(void) {
    uart_puts("\r\n");
    uart_puts("================================\r\n");
    uart_puts("  FreeRTOS QUEUE Demo\r\n");
    uart_puts("  Custom RISC-V CPU\r\n");
    uart_puts("================================\r\n\r\n");
    
    /* Create queue: 5 items, each sizeof(Message_t) */
    xDataQueue = xQueueCreate(5, sizeof(Message_t));
    
    if (xDataQueue != NULL) {
        uart_puts("[OK] Queue created (5 slots)!\r\n\r\n");
        
        /* Create tasks */
        xTaskCreate(vProducerTask, "Prod", 256, NULL, 1, NULL);
        xTaskCreate(vConsumerTask, "Cons", 256, NULL, 2, NULL);  /* Higher priority */
        
        /* Start scheduler */
        vTaskStartScheduler();
    } else {
        uart_puts("[FAIL] Queue creation failed!\r\n");
    }
    
    for (;;);
}

