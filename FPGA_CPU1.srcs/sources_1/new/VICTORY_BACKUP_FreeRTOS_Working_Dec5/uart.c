#include <stdint.h>
#include "uart.h"

#define UART_TX_ADDR   0xFFFFFFF0u
#define UART_STAT_ADDR 0xFFFFFFF4u

#define read_csr(reg) ({ \
    uint32_t __tmp; \
    asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
    __tmp; })

#define write_csr(reg, val) ({ \
    asm volatile ("csrw " #reg ", %0" :: "r"(val)); })

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
    uint32_t mstatus = read_csr(mstatus);
    uint32_t saved = mstatus;
    write_csr(mstatus, mstatus & ~0x8u);
    while (*s) {
        uart_putc(*s++);
    }
    write_csr(mstatus, saved);
}

void uart_print_hex(uint32_t val) {
    const char hex[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex[(val >> i) & 0xF]);
    }
}
