/*
 * TRAP DEBUG TEST SUITE
 * =====================
 * Tests trap handling WITHOUT FreeRTOS complexity.
 * Each test isolates one mechanism to identify the root cause.
 * 
 * Run with: build_debug.sh trap_test
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

/* Test results */
volatile uint32_t g_trap_count = 0;
volatile uint32_t g_last_mcause = 0;
volatile uint32_t g_last_mepc = 0;
volatile uint32_t g_test_passed = 0;

/* Saved context for manual context switch test */
volatile uint32_t g_saved_sp = 0;
volatile uint32_t g_saved_mepc = 0;

/*==========================================================================
 * SIMPLE TRAP HANDLER (no context switch, just count and return)
 *=========================================================================*/
__attribute__((naked, aligned(4)))
void simple_trap_handler(void) {
    __asm volatile (
        /* Save minimal context */
        "addi sp, sp, -16        \n"
        "sw   ra, 0(sp)          \n"
        "sw   t0, 4(sp)          \n"
        "sw   t1, 8(sp)          \n"
        "sw   t2, 12(sp)         \n"
        
        /* Read trap cause */
        "csrr t0, mcause         \n"
        "la   t1, g_last_mcause  \n"
        "sw   t0, 0(t1)          \n"
        
        /* Read mepc */
        "csrr t0, mepc           \n"
        "la   t1, g_last_mepc    \n"
        "sw   t0, 0(t1)          \n"
        
        /* Increment trap count */
        "la   t1, g_trap_count   \n"
        "lw   t0, 0(t1)          \n"
        "addi t0, t0, 1          \n"
        "sw   t0, 0(t1)          \n"
        
        /* Check if exception (mcause bit 31 = 0) or interrupt (bit 31 = 1) */
        "csrr t0, mcause         \n"
        "srli t1, t0, 31         \n"
        "bnez t1, 1f             \n"  /* If interrupt, skip mepc advance */
        
        /* Exception: advance mepc past the instruction */
        "csrr t0, mepc           \n"
        "addi t0, t0, 4          \n"
        "csrw mepc, t0           \n"
        "j    2f                 \n"
        
    "1: \n"  /* Interrupt: clear timer by setting MTIMECMP to max */
        "li   t0, 0xFFFF0010     \n"  /* MTIMECMP_LO */
        "li   t1, -1             \n"
        "sw   t1, 0(t0)          \n"  /* MTIMECMP_LO = 0xFFFFFFFF */
        "sw   t1, 4(t0)          \n"  /* MTIMECMP_HI = 0xFFFFFFFF */
        
    "2: \n"
        /* Restore minimal context */
        "lw   ra, 0(sp)          \n"
        "lw   t0, 4(sp)          \n"
        "lw   t1, 8(sp)          \n"
        "lw   t2, 12(sp)         \n"
        "addi sp, sp, 16         \n"
        
        "mret                    \n"
    );
}

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

static void print_pass(const char *test) {
    uart_puts("  [PASS] "); uart_puts(test); uart_puts("\r\n");
    g_test_passed++;
}

static void print_fail(const char *test, const char *reason) {
    uart_puts("  [FAIL] "); uart_puts(test); 
    uart_puts(" - "); uart_puts(reason); uart_puts("\r\n");
}

/*==========================================================================
 * TEST 1: ECALL (Environment Call Exception)
 * Tests: basic trap entry/exit, mepc advance
 *=========================================================================*/
static void test_ecall(void) {
    uart_puts("\r\n--- TEST 1: ECALL Exception ---\r\n");
    
    /* Install trap handler */
    write_csr(mtvec, (uint32_t)simple_trap_handler);
    uart_puts("  mtvec = "); print_hex(read_csr(mtvec)); uart_puts("\r\n");
    
    /* Clear counters */
    g_trap_count = 0;
    g_last_mcause = 0xDEADBEEF;
    
    /* Enable interrupts (though ecall is synchronous) */
    write_csr(mstatus, 0x8);  /* MIE = 1 */
    
    uart_puts("  Triggering ecall...\r\n");
    
    /* Trigger ecall */
    __asm volatile ("ecall");
    
    /* Check results */
    uart_puts("  After ecall:\r\n");
    uart_puts("    trap_count = "); print_dec(g_trap_count); uart_puts("\r\n");
    uart_puts("    mcause = "); print_hex(g_last_mcause); uart_puts("\r\n");
    uart_puts("    mepc = "); print_hex(g_last_mepc); uart_puts("\r\n");
    
    if (g_trap_count == 1 && (g_last_mcause == 11 || g_last_mcause == 0xB)) {
        print_pass("ecall trap and return");
    } else if (g_trap_count == 0) {
        print_fail("ecall", "trap handler not called");
    } else {
        print_fail("ecall", "wrong mcause");
    }
}

/*==========================================================================
 * TEST 2: EBREAK Exception
 * Tests: another exception type
 *=========================================================================*/
static void test_ebreak(void) {
    uart_puts("\r\n--- TEST 2: EBREAK Exception ---\r\n");
    
    g_trap_count = 0;
    g_last_mcause = 0xDEADBEEF;
    
    uart_puts("  Triggering ebreak...\r\n");
    
    __asm volatile ("ebreak");
    
    uart_puts("  After ebreak:\r\n");
    uart_puts("    trap_count = "); print_dec(g_trap_count); uart_puts("\r\n");
    uart_puts("    mcause = "); print_hex(g_last_mcause); uart_puts("\r\n");
    
    if (g_trap_count == 1 && g_last_mcause == 3) {
        print_pass("ebreak trap and return");
    } else if (g_trap_count == 0) {
        print_fail("ebreak", "trap handler not called");
    } else {
        print_fail("ebreak", "wrong mcause (expected 3)");
    }
}

/*==========================================================================
 * TEST 3: Timer Interrupt
 * Tests: asynchronous interrupt, mie/mip bits
 *=========================================================================*/
static void test_timer_interrupt(void) {
    uart_puts("\r\n--- TEST 3: Timer Interrupt ---\r\n");
    
    /* Disable interrupts during setup */
    write_csr(mstatus, 0);
    write_csr(mie, 0);
    
    g_trap_count = 0;
    g_last_mcause = 0xDEADBEEF;
    
    /* Read current MTIME */
    uint32_t now = MTIME_LO;
    uart_puts("  MTIME = "); print_dec(now); uart_puts("\r\n");
    
    /* Set MTIMECMP to trigger in 1000 cycles (very soon) */
    uint32_t target = now + 1000;
    MTIMECMP_HI = 0;
    MTIMECMP_LO = target;
    uart_puts("  MTIMECMP = "); print_dec(target); uart_puts("\r\n");
    
    /* Enable timer interrupt (MTIE = bit 7) */
    write_csr(mie, (1 << 7));
    uart_puts("  mie = "); print_hex(read_csr(mie)); uart_puts("\r\n");
    
    /* Check MIP.MTIP (should be 0 before time passes) */
    uart_puts("  mip before = "); print_hex(read_csr(mip)); uart_puts("\r\n");
    
    /* Enable global interrupts */
    uart_puts("  Enabling MIE...\r\n");
    write_csr(mstatus, 0x8);
    
    /* Wait a bit for timer to fire */
    for (volatile int i = 0; i < 5000; i++) {
        __asm volatile ("nop");
    }
    
    /* Check results */
    uart_puts("  After wait:\r\n");
    uart_puts("    trap_count = "); print_dec(g_trap_count); uart_puts("\r\n");
    uart_puts("    mcause = "); print_hex(g_last_mcause); uart_puts("\r\n");
    
    /* Disable interrupts */
    write_csr(mstatus, 0);
    write_csr(mie, 0);
    MTIMECMP_LO = 0xFFFFFFFF;
    MTIMECMP_HI = 0xFFFFFFFF;
    
    if (g_trap_count >= 1 && g_last_mcause == 0x80000007) {
        print_pass("timer interrupt");
    } else if (g_trap_count == 0) {
        print_fail("timer", "interrupt never fired");
        uart_puts("    Check: Is MIP.MTIP set? mip="); print_hex(read_csr(mip)); uart_puts("\r\n");
    } else {
        print_fail("timer", "wrong mcause (expected 0x80000007)");
    }
}

/*==========================================================================
 * TEST 4: Multiple Traps in Sequence
 * Tests: trap handler stability, no state corruption
 *=========================================================================*/
static void test_multiple_traps(void) {
    uart_puts("\r\n--- TEST 4: Multiple Sequential Traps ---\r\n");
    
    g_trap_count = 0;
    
    uart_puts("  Triggering 10 ecalls...\r\n");
    
    for (int i = 0; i < 10; i++) {
        __asm volatile ("ecall");
    }
    
    uart_puts("    trap_count = "); print_dec(g_trap_count); uart_puts("\r\n");
    
    if (g_trap_count == 10) {
        print_pass("10 sequential traps");
    } else {
        print_fail("sequential traps", "count mismatch");
    }
}

/*==========================================================================
 * TEST 5: Stack Pointer Preservation
 * Tests: SP is correctly saved/restored across trap
 *=========================================================================*/
static void test_stack_preservation(void) {
    uart_puts("\r\n--- TEST 5: Stack Pointer Preservation ---\r\n");
    
    g_trap_count = 0;
    
    uint32_t sp_before, sp_after;
    
    __asm volatile (
        "mv %0, sp\n"
        : "=r"(sp_before)
    );
    
    uart_puts("  SP before ecall = "); print_hex(sp_before); uart_puts("\r\n");
    
    __asm volatile ("ecall");
    
    __asm volatile (
        "mv %0, sp\n"
        : "=r"(sp_after)
    );
    
    uart_puts("  SP after ecall  = "); print_hex(sp_after); uart_puts("\r\n");
    
    if (sp_before == sp_after) {
        print_pass("SP preserved across trap");
    } else {
        print_fail("SP preservation", "SP changed!");
    }
}

/*==========================================================================
 * TEST 6: Callee-Saved Register Preservation
 * Tests: s0-s11 are preserved across trap
 *=========================================================================*/
static void test_register_preservation(void) {
    uart_puts("\r\n--- TEST 6: Register Preservation ---\r\n");
    
    g_trap_count = 0;
    
    uint32_t s0_before, s0_after;
    uint32_t s1_before, s1_after;
    
    /* Set known values in callee-saved registers and read back using temp regs */
    __asm volatile (
        "li s0, 0xDEADBEEF\n"
        "li s1, 0xCAFEBABE\n"
        "mv t0, s0\n"
        "mv t1, s1\n"
        "mv %0, t0\n"
        "mv %1, t1\n"
        : "=r"(s0_before), "=r"(s1_before)
        :
        : "s0", "s1", "t0", "t1"
    );
    
    uart_puts("  s0 before = "); print_hex(s0_before); uart_puts("\r\n");
    uart_puts("  s1 before = "); print_hex(s1_before); uart_puts("\r\n");
    
    __asm volatile ("ecall");
    
    /* Read s0/s1 using temp registers to avoid compiler using s0/s1 as outputs */
    __asm volatile (
        "mv t0, s0\n"
        "mv t1, s1\n"
        "mv %0, t0\n"
        "mv %1, t1\n"
        : "=r"(s0_after), "=r"(s1_after)
        :
        : "t0", "t1"
    );
    
    uart_puts("  s0 after  = "); print_hex(s0_after); uart_puts("\r\n");
    uart_puts("  s1 after  = "); print_hex(s1_after); uart_puts("\r\n");
    
    if (s0_before == s0_after && s1_before == s1_after) {
        print_pass("callee-saved registers preserved");
    } else {
        print_fail("register preservation", "s0/s1 corrupted");
    }
}

/*==========================================================================
 * TEST 7: MRET Behavior
 * Tests: mret correctly jumps to mepc and sets MIE from MPIE
 *=========================================================================*/
static void test_mret_behavior(void) {
    uart_puts("\r\n--- TEST 7: MRET Behavior ---\r\n");
    
    /* Read mstatus before trap */
    uint32_t mstatus_before = read_csr(mstatus);
    uart_puts("  mstatus before = "); print_hex(mstatus_before); uart_puts("\r\n");
    
    __asm volatile ("ecall");
    
    /* Read mstatus after trap (mret should have restored MIE from MPIE) */
    uint32_t mstatus_after = read_csr(mstatus);
    uart_puts("  mstatus after  = "); print_hex(mstatus_after); uart_puts("\r\n");
    
    /* MIE bit (bit 3) should be restored */
    if ((mstatus_before & 0x8) == (mstatus_after & 0x8)) {
        print_pass("mret restores MIE from MPIE");
    } else {
        print_fail("mret", "MIE not correctly restored");
    }
}

/*==========================================================================
 * MAIN TEST RUNNER
 *=========================================================================*/
int main(void) {
    uart_puts("\r\n");
    uart_puts("================================================\r\n");
    uart_puts("   TRAP DEBUG TEST SUITE\r\n");
    uart_puts("================================================\r\n");
    uart_puts("This tests trap handling WITHOUT FreeRTOS.\r\n");
    uart_puts("If these tests fail, the issue is in CPU/trap.\r\n");
    uart_puts("If they pass, the issue is in FreeRTOS port.\r\n");
    uart_puts("================================================\r\n");
    
    /* Ensure clean state */
    write_csr(mstatus, 0);
    write_csr(mie, 0);
    MTIMECMP_LO = 0xFFFFFFFF;
    MTIMECMP_HI = 0xFFFFFFFF;
    
    /* Run tests */
    test_ecall();
    test_ebreak();
    test_timer_interrupt();
    test_multiple_traps();
    test_stack_preservation();
    test_register_preservation();
    test_mret_behavior();
    
    /* Summary */
    uart_puts("\r\n");
    uart_puts("================================================\r\n");
    uart_puts("   TEST SUMMARY: ");
    print_dec(g_test_passed);
    uart_puts("/7 passed\r\n");
    uart_puts("================================================\r\n");
    
    if (g_test_passed == 7) {
        uart_puts("\r\n*** ALL TESTS PASSED ***\r\n");
        uart_puts("CPU trap handling is working correctly.\r\n");
        uart_puts("Issue is likely in FreeRTOS port context switch.\r\n");
    } else {
        uart_puts("\r\n*** SOME TESTS FAILED ***\r\n");
        uart_puts("Fix CPU trap handling before debugging FreeRTOS.\r\n");
    }
    
    uart_puts("\r\n[END OF TRAP TESTS]\r\n");
    
    /* Infinite loop */
    for (;;) {
        __asm volatile ("wfi");
    }
}

/* Required by linker */
void vTaskStartScheduler(void) {
    /* Not used in this test */
    for (;;);
}

