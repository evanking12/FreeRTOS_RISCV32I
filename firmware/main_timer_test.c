/*
 * TIMER INTERRUPT STRESS TEST
 * ============================
 * Tests timer interrupts with rapid MTIMECMP updates.
 * This is exactly what FreeRTOS does - updates MTIMECMP in the ISR.
 * 
 * Run with: build_debug.sh timer_test
 */

#include <stdint.h>
#include "uart.h"

/* CSR access macros */
#define read_csr(reg) ({ uint32_t v; __asm volatile ("csrr %0, " #reg : "=r"(v)); v; })
#define write_csr(reg, val) __asm volatile ("csrw " #reg ", %0" :: "rK"(val))

/* Timer registers */
#define MTIME_LO        (*(volatile uint32_t *)0xFFFF0008)
#define MTIME_HI        (*(volatile uint32_t *)0xFFFF000C)
#define MTIMECMP_LO     (*(volatile uint32_t *)0xFFFF0010)
#define MTIMECMP_HI     (*(volatile uint32_t *)0xFFFF0014)

/* Timer tick interval (1ms at 25MHz = 25000 cycles) */
#define TICK_INTERVAL   25000

/* Test state */
volatile uint32_t g_tick_count = 0;
volatile uint32_t g_last_mtime = 0;
volatile uint32_t g_tick_errors = 0;

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
 * TIMER INTERRUPT HANDLER
 * This mimics what FreeRTOS does:
 * 1. Read current MTIMECMP
 * 2. Add tick interval
 * 3. Write new MTIMECMP
 *=========================================================================*/
__attribute__((naked, aligned(4)))
void timer_trap_handler(void) {
    __asm volatile (
        /* Save minimal context */
        "addi sp, sp, -32        \n"
        "sw   ra, 0(sp)          \n"
        "sw   t0, 4(sp)          \n"
        "sw   t1, 8(sp)          \n"
        "sw   t2, 12(sp)         \n"
        "sw   t3, 16(sp)         \n"
        "sw   a0, 20(sp)         \n"
        "sw   a1, 24(sp)         \n"
        
        /* Check if timer interrupt */
        "csrr t0, mcause         \n"
        "li   t1, 0x80000007     \n"  /* Timer interrupt cause */
        "bne  t0, t1, 1f         \n"  /* Not timer? Skip */
        
        /* === TIMER INTERRUPT HANDLING === */
        
        /* Increment tick count */
        "la   t0, g_tick_count   \n"
        "lw   t1, 0(t0)          \n"
        "addi t1, t1, 1          \n"
        "sw   t1, 0(t0)          \n"
        
        /* Read current MTIMECMP_LO */
        "li   t0, 0xFFFF0010     \n"  /* MTIMECMP_LO address */
        "lw   t1, 0(t0)          \n"  /* t1 = current MTIMECMP */
        
        /* Calculate next = current + TICK_INTERVAL */
        "li   t2, 25000          \n"  /* TICK_INTERVAL */
        "add  t1, t1, t2         \n"  /* t1 = next MTIMECMP */
        
        /* Write new MTIMECMP (high word first to prevent spurious interrupt) */
        "li   t3, 0xFFFF0014     \n"  /* MTIMECMP_HI address */
        "sw   x0, 0(t3)          \n"  /* MTIMECMP_HI = 0 */
        "sw   t1, 0(t0)          \n"  /* MTIMECMP_LO = next */
        
        "j    2f                 \n"
        
    "1: \n"  /* Not a timer interrupt - check for exception */
        "csrr t0, mcause         \n"
        "srli t1, t0, 31         \n"
        "bnez t1, 2f             \n"  /* If interrupt bit set, skip */
        
        /* Exception: advance mepc */
        "csrr t0, mepc           \n"
        "addi t0, t0, 4          \n"
        "csrw mepc, t0           \n"
        
    "2: \n"
        /* Restore context */
        "lw   ra, 0(sp)          \n"
        "lw   t0, 4(sp)          \n"
        "lw   t1, 8(sp)          \n"
        "lw   t2, 12(sp)         \n"
        "lw   t3, 16(sp)         \n"
        "lw   a0, 20(sp)         \n"
        "lw   a1, 24(sp)         \n"
        "addi sp, sp, 32         \n"
        
        "mret                    \n"
    );
}

/*==========================================================================
 * MAIN TEST
 *=========================================================================*/
int main(void) {
    uart_puts("\r\n");
    uart_puts("================================================\r\n");
    uart_puts("   TIMER INTERRUPT STRESS TEST\r\n");
    uart_puts("================================================\r\n");
    uart_puts("Tests rapid timer interrupt handling.\r\n");
    uart_puts("Tick interval: 25000 cycles (1ms at 25MHz)\r\n");
    uart_puts("================================================\r\n\r\n");
    
    /* Disable interrupts during setup */
    write_csr(mstatus, 0);
    write_csr(mie, 0);
    
    /* Install trap handler */
    write_csr(mtvec, (uint32_t)timer_trap_handler);
    uart_puts("mtvec = "); print_hex(read_csr(mtvec)); uart_puts("\r\n");
    
    /* Read current MTIME */
    uint32_t now = MTIME_LO;
    uart_puts("MTIME = "); print_dec(now); uart_puts("\r\n");
    
    /* Set first MTIMECMP */
    MTIMECMP_HI = 0;
    MTIMECMP_LO = now + TICK_INTERVAL;
    uart_puts("MTIMECMP = "); print_dec(MTIMECMP_LO); uart_puts("\r\n");
    
    /* Enable timer interrupt */
    write_csr(mie, (1 << 7));  /* MTIE only */
    uart_puts("mie = "); print_hex(read_csr(mie)); uart_puts("\r\n");
    
    /* Enable global interrupts */
    uart_puts("\r\n--- Enabling interrupts ---\r\n");
    write_csr(mstatus, 0x8);  /* MIE = 1 */
    
    /* Main loop - let timer interrupts run */
    uint32_t last_report = 0;
    uint32_t target_ticks = 100;  /* Run for 100 ticks (100ms) */
    
    uart_puts("Waiting for ");
    print_dec(target_ticks);
    uart_puts(" timer ticks...\r\n\r\n");
    
    while (g_tick_count < target_ticks) {
        /* Report every 10 ticks */
        if (g_tick_count >= last_report + 10) {
            last_report = g_tick_count;
            uart_puts("  [tick ");
            print_dec(g_tick_count);
            uart_puts("] MTIME=");
            print_dec(MTIME_LO);
            uart_puts(" MTIMECMP=");
            print_dec(MTIMECMP_LO);
            uart_puts("\r\n");
        }
        
        /* Use WFI to wait for interrupt */
        __asm volatile ("wfi");
    }
    
    /* Disable interrupts */
    write_csr(mstatus, 0);
    write_csr(mie, 0);
    
    /* Results */
    uart_puts("\r\n");
    uart_puts("================================================\r\n");
    uart_puts("   TIMER TEST RESULTS\r\n");
    uart_puts("================================================\r\n");
    uart_puts("Total ticks: ");
    print_dec(g_tick_count);
    uart_puts("\r\n");
    uart_puts("Expected:    ");
    print_dec(target_ticks);
    uart_puts("\r\n");
    
    if (g_tick_count >= target_ticks) {
        uart_puts("\r\n*** TIMER TEST PASSED ***\r\n");
        uart_puts("Timer interrupts work correctly!\r\n");
    } else {
        uart_puts("\r\n*** TIMER TEST FAILED ***\r\n");
        uart_puts("Not enough ticks received.\r\n");
    }
    
    uart_puts("================================================\r\n");
    uart_puts("[END OF TIMER TEST]\r\n");
    
    for (;;) {
        __asm volatile ("wfi");
    }
}

/* Required by linker */
void vTaskStartScheduler(void) {
    for (;;);
}

