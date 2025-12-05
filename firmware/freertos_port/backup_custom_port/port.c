#include "FreeRTOS.h"
#include "task.h"
#include <stdint.h>

extern void vPortStartFirstTask( void );
extern void vPortYieldHandler( void );
void vPortYield( void );
void vTaskSwitchContext( void );

/* Machine CSRs */
#define read_csr(reg) ({ uint32_t v; __asm volatile ("csrr %0, " #reg : "=r"(v)); v; })
#define write_csr(reg, val) __asm volatile ("csrw " #reg ", %0" :: "rK"(val))

/* Memory-mapped CLINT-style timer (32-bit access) */
/* MTIME and MTIMECMP are 64-bit but accessed as 32-bit halves */
#define MTIME_LO     (*(volatile uint32_t *)(configMTIME_BASE_ADDRESS))
#define MTIME_HI     (*(volatile uint32_t *)(configMTIME_BASE_ADDRESS + 4))
#define MTIMECMP_LO  (*(volatile uint32_t *)(configMTIMECMP_BASE_ADDRESS))
#define MTIMECMP_HI  (*(volatile uint32_t *)(configMTIMECMP_BASE_ADDRESS + 4))

/* Helper to read 64-bit mtime safely */
static inline uint64_t read_mtime(void) {
    uint32_t lo, hi;
    do {
        hi = MTIME_HI;
        lo = MTIME_LO;
    } while (hi != MTIME_HI);  /* Handle rollover */
    return ((uint64_t)hi << 32) | lo;
}

/* Helper to write 64-bit mtimecmp safely */
static inline void write_mtimecmp(uint64_t val) {
    /* Set high word to max to prevent spurious interrupts during update */
    MTIMECMP_HI = 0xFFFFFFFF;
    MTIMECMP_LO = (uint32_t)val;
    MTIMECMP_HI = (uint32_t)(val >> 32);
}

/* Forward declaration */
void vPortSetupTimerInterrupt( void );

/*-----------------------------------------------------------*/

/* UART debug helper - inline to avoid call overhead */
static inline void port_debug_char(char c) {
    volatile uint32_t *uart_stat = (volatile uint32_t *)0xFFFFFFF4u;
    volatile uint32_t *uart_tx   = (volatile uint32_t *)0xFFFFFFF0u;
    while (*uart_stat & 0x3);  /* wait for TX ready */
    *uart_tx = c;
}
static inline void port_debug_str(const char *s) {
    while (*s) port_debug_char(*s++);
}

BaseType_t xPortStartScheduler( void )
{
    port_debug_str("\r\n");
    port_debug_str("========================================\r\n");
    port_debug_str("=== xPortStartScheduler ENTRY ===\r\n");
    port_debug_str("========================================\r\n");
    
    /* Step A: Disable all interrupts */
    port_debug_str("[SCHED-A] Disabling all interrupts...\r\n");
    write_csr(mstatus, 0);
    write_csr(mie, 0);
    uint32_t ms = read_csr(mstatus);
    uint32_t mi = read_csr(mie);
    port_debug_str("  mstatus="); 
    for(int i=7; i>=0; i--) port_debug_char('0' + ((ms >> (i*4)) & 0xF));
    port_debug_str(" mie=");
    for(int i=7; i>=0; i--) port_debug_char('0' + ((mi >> (i*4)) & 0xF));
    port_debug_str("\r\n");

    /* Step B: Setup timer */
    port_debug_str("[SCHED-B] Setting up timer interrupt...\r\n");
    port_debug_str("  Tick rate: 1000 Hz\r\n");
    port_debug_str("  CPU clock: 25 MHz\r\n");
    port_debug_str("  Ticks per interrupt: 25000\r\n");
    vPortSetupTimerInterrupt();
    port_debug_str("  Timer setup complete.\r\n");

    /* Step C: Enable MTIE in mie */
    port_debug_str("[SCHED-C] Enabling mie.MTIE...\r\n");
    write_csr(mie, (1 << 7));
    mi = read_csr(mie);
    port_debug_str("  mie after enable: 0x");
    for(int i=7; i>=0; i--) port_debug_char("0123456789ABCDEF"[(mi >> (i*4)) & 0xF]);
    port_debug_str("\r\n");
    
    /* Step D: Check mtvec before calling vPortStartFirstTask */
    port_debug_str("[SCHED-D] About to call vPortStartFirstTask...\r\n");
    uint32_t tv = read_csr(mtvec);
    port_debug_str("  mtvec before: 0x");
    for(int i=7; i>=0; i--) port_debug_char("0123456789ABCDEF"[(tv >> (i*4)) & 0xF]);
    port_debug_str("\r\n");
    
    port_debug_str("  Calling vPortStartFirstTask() NOW...\r\n");
    
    /* Start first task - this sets mtvec, enables MIE, and never returns */
    vPortStartFirstTask();

    /* Should never get here */
    port_debug_str("\r\n!!! ERROR: vPortStartFirstTask returned !!!\r\n");
    port_debug_str("This should NEVER happen!\r\n");
    return pdFALSE;
}

/*-----------------------------------------------------------*/

void vPortEndScheduler( void )
{
    /* Not implemented */
    for( ;; );
}

/*-----------------------------------------------------------*/

void vPortSetupTimerInterrupt( void )
{
    /* First tick: +100,000 cycles = 1ms at 100MHz */
    uint64_t now = read_mtime();
    write_mtimecmp(now + (configCPU_CLOCK_HZ / configTICK_RATE_HZ));
}

/*-----------------------------------------------------------*/

/* Debug functions called from assembly */
void debug_putchar(uint32_t c) {
    port_debug_char((char)c);
}

void debug_print_mepc(uint32_t val) {
    port_debug_str("[DEBUG] val=0x");
    for(int i=7; i>=0; i--) port_debug_char("0123456789ABCDEF"[(val >> (i*4)) & 0xF]);
    port_debug_str("\r\n");
}

/* Machine trap handler installed in portASM.S */
void vPortSysTickHandler( void )
{
    static uint32_t tick_count = 0;
    tick_count++;
    
    /* Debug: show we're in the tick handler */
    if (tick_count <= 5 || (tick_count % 1000) == 0) {
        port_debug_str("[TICK ");
        /* Quick decimal print */
        char buf[12]; int i = 0; uint32_t v = tick_count;
        if (v == 0) buf[i++] = '0';
        else { while (v) { buf[i++] = '0' + (v % 10); v /= 10; } }
        while (i > 0) port_debug_char(buf[--i]);
        port_debug_str("]\r\n");
    }
    
    /* Read current mtimecmp and schedule next tick */
    uint64_t cmp_lo = MTIMECMP_LO;
    uint64_t cmp_hi = MTIMECMP_HI;
    uint64_t current_cmp = (cmp_hi << 32) | cmp_lo;
    uint64_t next = current_cmp + (configCPU_CLOCK_HZ / configTICK_RATE_HZ);
    write_mtimecmp(next);

    /* Run FreeRTOS tick */
    if( xTaskIncrementTick() != pdFALSE )
    {
        /* Debug: context switch happening */
        if (tick_count <= 10) {
            port_debug_str("[CTX_SW @tick ");
            char buf[12]; int i = 0; uint32_t v = tick_count;
            if (v == 0) buf[i++] = '0';
            else { while (v) { buf[i++] = '0' + (v % 10); v /= 10; } }
            while (i > 0) port_debug_char(buf[--i]);
            port_debug_str("]\r\n");
        }
        vTaskSwitchContext(); /* switch to next ready task */
    }
}

/* Request context switch */
void vPortYield( void )
{
    __asm volatile ("ecall");
}

/* Yield handler called from trap on ECALL */
void vPortYieldHandler( void )
{
    static uint32_t yield_count = 0;
    yield_count++;
    if (yield_count <= 5) {
        port_debug_str("[YIELD]\r\n");
    }
    vTaskSwitchContext();
}

