#ifndef PORTMACRO_H
#define PORTMACRO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*-----------------------------------------------------------
 * Type definitions
 *----------------------------------------------------------*/

typedef uint32_t StackType_t;
typedef int32_t  BaseType_t;
typedef uint32_t UBaseType_t;
typedef uint32_t TickType_t;

/*-----------------------------------------------------------
 * Architecture specifics
 *----------------------------------------------------------*/

#define portSTACK_GROWTH            ( -1 )
#define portTICK_PERIOD_MS          ( ( TickType_t ) 1000 / ( TickType_t ) configTICK_RATE_HZ )
#define portBYTE_ALIGNMENT          4
#define portPOINTER_SIZE_TYPE       uint32_t
#define portNOP()                   __asm volatile( "nop" )
#define portMAX_DELAY               ( TickType_t )0xffffffffUL
#define portCRITICAL_NESTING_IN_TCB    0
#define portARCH_NAME                  "RISC-V"

/*-----------------------------------------------------------
 * Scheduler utilities
 *----------------------------------------------------------*/

/* Trigger a yield via ECALL. */
#define portYIELD()                 __asm volatile( "ecall" )
#define portYIELD_FROM_ISR(x)       do { if( ( x ) != 0 ) portYIELD(); } while(0)

/*-----------------------------------------------------------
 * Critical section control
 *----------------------------------------------------------*/

/* MIE bit in mstatus is bit 3. */
#define portDISABLE_INTERRUPTS()    __asm volatile( "csrc mstatus, 8" )
#define portENABLE_INTERRUPTS()     __asm volatile( "csrs mstatus, 8" )

#define portENTER_CRITICAL()        portDISABLE_INTERRUPTS()
#define portEXIT_CRITICAL()         portENABLE_INTERRUPTS()

/* No mask save/restore needed for this simple port. */
#define portSET_INTERRUPT_MASK_FROM_ISR()    0
#define portCLEAR_INTERRUPT_MASK_FROM_ISR(x) ( void )( x )

/*-----------------------------------------------------------
 * Task function macros
 *----------------------------------------------------------*/

#define portTASK_FUNCTION_PROTO( vFunction, pvParameters ) void vFunction( void *pvParameters )
#define portTASK_FUNCTION( vFunction, pvParameters )       void vFunction( void *pvParameters )

/*-----------------------------------------------------------
 * Port annotations (empty for this non-MPU build)
 *----------------------------------------------------------*/
#define PRIVILEGED_FUNCTION
#define PRIVILEGED_DATA
#define portDONT_DISCARD               __attribute__((used))

#ifdef __cplusplus
}
#endif

#endif /* PORTMACRO_H */
