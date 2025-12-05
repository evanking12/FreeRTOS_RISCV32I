/*
 * Chip-specific extensions for custom RISC-V CPU with CLINT
 * Memory map:
 *   MTIME:    0xFFFF0008
 *   MTIMECMP: 0xFFFF0010
 */

#ifndef __FREERTOS_RISC_V_EXTENSIONS_H__
#define __FREERTOS_RISC_V_EXTENSIONS_H__

#define portasmHAS_SIFIVE_CLINT 0  /* We don't have standard CLINT layout */
#define portasmHAS_MTIME 1         /* We do have MTIME register */
#define portasmADDITIONAL_CONTEXT_SIZE 0 /* No additional registers to save */

.macro portasmSAVE_ADDITIONAL_REGISTERS
    /* No additional registers to save */
    .endm

.macro portasmRESTORE_ADDITIONAL_REGISTERS
    /* No additional registers to restore */
    .endm

#endif /* __FREERTOS_RISC_V_EXTENSIONS_H__ */
