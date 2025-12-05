/*
 * FreeRTOS Kernel V10.5.1 - RISC-V Port Macros
 * Adapted for custom RISC-V CPU (RV32I)
 */

#ifndef PORTMACRO_H
#define PORTMACRO_H

#ifdef __cplusplus
extern "C" {
#endif

/*-----------------------------------------------------------
 * Port specific definitions.
 *-----------------------------------------------------------*/

/* Type definitions for RV32I */
#define portSTACK_TYPE          uint32_t
#define portBASE_TYPE           int32_t
#define portUBASE_TYPE          uint32_t
#define portMAX_DELAY           ( TickType_t ) 0xffffffffUL

typedef portSTACK_TYPE StackType_t;
typedef portBASE_TYPE BaseType_t;
typedef portUBASE_TYPE UBaseType_t;
typedef portUBASE_TYPE TickType_t;

/* Legacy type definitions */
#define portCHAR            char
#define portFLOAT           float
#define portDOUBLE          double
#define portLONG            long
#define portSHORT           short

/* 32-bit tick type on a 32-bit architecture */
#define portTICK_TYPE_IS_ATOMIC 1
/*-----------------------------------------------------------*/

/* Architecture specifics */
#define portSTACK_GROWTH            ( -1 )
#define portTICK_PERIOD_MS          ( ( TickType_t ) 1000 / configTICK_RATE_HZ )
#define portBYTE_ALIGNMENT          16
/*-----------------------------------------------------------*/

/* Scheduler utilities */
extern void vTaskSwitchContext( void );
#define portYIELD() __asm volatile( "ecall" );
#define portEND_SWITCHING_ISR( xSwitchRequired ) do { if( xSwitchRequired ) vTaskSwitchContext(); } while( 0 )
#define portYIELD_FROM_ISR( x ) portEND_SWITCHING_ISR( x )
/*-----------------------------------------------------------*/

/* Critical section management */
#define portCRITICAL_NESTING_IN_TCB                             0

#define portSET_INTERRUPT_MASK_FROM_ISR()                       0
#define portCLEAR_INTERRUPT_MASK_FROM_ISR( uxSavedStatusValue ) ( void ) uxSavedStatusValue

#define portDISABLE_INTERRUPTS()    __asm volatile( "csrc mstatus, 8" )
#define portENABLE_INTERRUPTS()     __asm volatile( "csrs mstatus, 8" )

extern size_t xCriticalNesting;
#define portENTER_CRITICAL()            \
{                                       \
    portDISABLE_INTERRUPTS();           \
    xCriticalNesting++;                 \
}

#define portEXIT_CRITICAL()             \
{                                       \
    xCriticalNesting--;                 \
    if( xCriticalNesting == 0 )         \
    {                                   \
        portENABLE_INTERRUPTS();        \
    }                                   \
}
/*-----------------------------------------------------------*/

/* Architecture specific optimisations */
#ifndef configUSE_PORT_OPTIMISED_TASK_SELECTION
    #define configUSE_PORT_OPTIMISED_TASK_SELECTION 1
#endif

#if( configUSE_PORT_OPTIMISED_TASK_SELECTION == 1 )

    #if( configMAX_PRIORITIES > 32 )
        #error configUSE_PORT_OPTIMISED_TASK_SELECTION can only be set to 1 when configMAX_PRIORITIES is less than or equal to 32.
    #endif

    #define portRECORD_READY_PRIORITY( uxPriority, uxReadyPriorities ) ( uxReadyPriorities ) |= ( 1UL << ( uxPriority ) )
    #define portRESET_READY_PRIORITY( uxPriority, uxReadyPriorities ) ( uxReadyPriorities ) &= ~( 1UL << ( uxPriority ) )
    #define portGET_HIGHEST_PRIORITY( uxTopPriority, uxReadyPriorities ) uxTopPriority = ( 31UL - __builtin_clz( uxReadyPriorities ) )

#endif /* configUSE_PORT_OPTIMISED_TASK_SELECTION */
/*-----------------------------------------------------------*/

/* Task function macros */
#define portTASK_FUNCTION_PROTO( vFunction, pvParameters ) void vFunction( void *pvParameters )
#define portTASK_FUNCTION( vFunction, pvParameters ) void vFunction( void *pvParameters )
/*-----------------------------------------------------------*/

#define portNOP()    __asm volatile( " nop " )
#define portINLINE   __inline

#ifndef portFORCE_INLINE
    #define portFORCE_INLINE inline __attribute__(( always_inline))
#endif

#define portMEMORY_BARRIER() __asm volatile( "" ::: "memory" )
/*-----------------------------------------------------------*/

#ifdef __cplusplus
}
#endif

#endif /* PORTMACRO_H */
