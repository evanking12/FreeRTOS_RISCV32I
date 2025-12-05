#ifndef UART_H
#define UART_H

#include <stdint.h>

void uart_putc(char c);
void uart_puts(const char *s);
void uart_print_hex(uint32_t val);

#endif
