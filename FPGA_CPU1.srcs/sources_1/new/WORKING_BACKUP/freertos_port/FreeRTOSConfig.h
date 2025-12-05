/*
 * FreeRTOS Configuration for Custom RISC-V CPU
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* System clock and tick configuration */
#define configCPU_CLOCK_HZ            ( 25000000UL )  /* 25 MHz */
#define configTICK_RATE_HZ            ( 1000U )       /* 1ms tick */

/* Timer addresses - MUST match cpu_core.v! */
#define configMTIME_BASE_ADDRESS      ( 0xFFFF0008UL )  /* MTIME register */
#define configMTIMECMP_BASE_ADDRESS   ( 0xFFFF0010UL )  /* MTIMECMP register */

/* Task configuration */
#define configMAX_PRIORITIES          ( 5 )
#define configMINIMAL_STACK_SIZE      ( 512 )  /* Increased for trap handler overhead */
#define configTOTAL_HEAP_SIZE         ( 20 * 1024 )
#define configMAX_TASK_NAME_LEN       ( 16 )
#define configUSE_16_BIT_TICKS        0

/* Scheduler configuration */
#define configUSE_PREEMPTION          1
#define configUSE_IDLE_HOOK           1
#define configUSE_TICK_HOOK           1

/* Optional features */
#define INCLUDE_vTaskDelay            1
#define INCLUDE_xTaskDelayUntil       1
#define INCLUDE_xTaskGetTickCount     1
#define INCLUDE_vTaskDelete           0
#define INCLUDE_vTaskSuspend          0

/* Mutex and timer configuration */
#define configUSE_MUTEXES             1
#define configUSE_TIMERS              0   /* Disable software timers for now */

/* Memory allocation */
#define configSUPPORT_DYNAMIC_ALLOCATION 1

/* Debugging and assertions - simple version */
#define configASSERT(x) if ((x)==0) { taskDISABLE_INTERRUPTS(); for(;;); }

/* Stack overflow detection */
#define configCHECK_FOR_STACK_OVERFLOW 2

/* ISR stack size (in words) */
#define configISR_STACK_SIZE_WORDS    256

#endif /* FREERTOS_CONFIG_H */
