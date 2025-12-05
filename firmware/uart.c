#include <stdint.h>
#include "uart.h"

#define UART_TX_ADDR   0xFFFFFFF0u
#define UART_STAT_ADDR 0xFFFFFFF4u

static inline uint32_t uart_status(void) {
    return *(volatile uint32_t *)UART_STAT_ADDR;
}

void uart_putc(char c) {
    while (uart_status() & 0x3u) {
        /* wait for not busy and fifo space */
    }
    *(volatile uint32_t *)UART_TX_ADDR = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s) {
    /* Note: caller should use taskENTER_CRITICAL() if atomicity needed */
    while (*s) {
        uart_putc(*s++);
    }
}

void uart_print_hex(uint32_t val) {
    const char hex[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex[(val >> i) & 0xF]);
    }
}
