#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#define configCPU_CLOCK_HZ            ( 25000000UL )  /* 25 MHz after clock divider (100/4) */
#define configTICK_RATE_HZ            ( 1000U )
#define configMAX_PRIORITIES          ( 5 )
#define configMINIMAL_STACK_SIZE      ( 512 )  /* Increased for debugging */
#define configTOTAL_HEAP_SIZE         ( 20 * 1024 )
#define configMAX_TASK_NAME_LEN       ( 16 )
#define configUSE_16_BIT_TICKS        0

#define configUSE_PREEMPTION          1
#define configUSE_IDLE_HOOK           1
#define configUSE_TICK_HOOK           1
#define INCLUDE_vTaskDelay            1
#define INCLUDE_xTaskDelayUntil       1
#define INCLUDE_xTaskGetTickCount     1

#define configUSE_MUTEXES             1
#define configUSE_TIMERS              1
#define configTIMER_TASK_PRIORITY     2
#define configTIMER_QUEUE_LENGTH      5
#define configTIMER_TASK_STACK_DEPTH  configMINIMAL_STACK_SIZE

#define configSUPPORT_DYNAMIC_ALLOCATION 1

#define configASSERT(x) if ((x)==0) { taskDISABLE_INTERRUPTS(); for(;;); }

/* CLINT Timer addresses - MUST match cpu_core.v! */
#define configMTIME_BASE_ADDRESS     ( 0xFFFF0008UL )  /* CLINT_MTIME_LO */
#define configMTIMECMP_BASE_ADDRESS  ( 0xFFFF0010UL )  /* CLINT_MTIMECMP_LO */

#endif /* FREERTOS_CONFIG_H */
