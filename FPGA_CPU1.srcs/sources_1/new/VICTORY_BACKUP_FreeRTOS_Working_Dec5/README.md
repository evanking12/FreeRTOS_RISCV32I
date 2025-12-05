# 🎉 FreeRTOS Running on Custom RISC-V CPU - VICTORY BACKUP

**Date:** December 5, 2025

## What This Is

A fully working FreeRTOS Real-Time Operating System running on a **custom-designed RISC-V CPU** implemented in Verilog on an FPGA.

## What's Demonstrated

- ✅ Custom RV32I RISC-V CPU with 3-stage pipeline
- ✅ Trap handling (ecall/mret) with proper context save/restore
- ✅ FreeRTOS kernel boot and task creation
- ✅ Multi-task scheduling with context switching
- ✅ Cooperative multitasking via taskYIELD()
- ✅ Critical sections for atomic operations
- ✅ UART output for debug/demo

## Key Files

### Firmware (`firmware/`)
- `main.c` - FreeRTOS demo with two tasks
- `crt0.s` - Startup assembly (trap handler setup, BSS clear, etc.)
- `freertos_port/portASM.S` - Context switch assembly
- `freertos_port/port.c` - FreeRTOS port C functions
- `freertos_port/FreeRTOSConfig.h` - RTOS configuration

### RTL / Hardware (`rtl/`)
- `cpu_core.v` - Main CPU pipeline with CSR handling
- `cpu_top.v` - Top-level CPU module with memory
- `pc_reg.v` - Program counter with async reset
- `top.v` - FPGA top with UART, LEDs, etc.

## Hardware Bugs Fixed During Development

1. `mret` was adding +4 to mepc (should just use mepc as-is)
2. Interrupt mepc save was using wrong PC value
3. CSR write conflict with mret mstatus update
4. Missing trap flush for register writeback
5. Memory writes not cancelled during trap flush
6. PC register reset race condition
7. Instruction fetch delay bug

## The Journey

This project involved extensive hardware-software co-debugging:
- Identified CPU bugs via simulation waveforms
- Fixed pipeline hazards affecting CSR operations
- Debugged context switch register corruption
- Got trap handlers working correctly
- Finally achieved stable FreeRTOS multitasking!

## How to Rebuild

```bash
cd firmware
./build_debug.sh freertos
```

Then regenerate FPGA bitstream and program.

## Skills Demonstrated

- Digital Logic Design (Verilog HDL)
- Computer Architecture (RISC-V, pipelining, CSRs)
- Systems Programming (Assembly, C, linker scripts)
- RTOS Internals (scheduling, context switching)
- Hardware-Software Co-Design & Debugging
- FPGA Development (Vivado, synthesis, timing)

---

*This was a challenging but rewarding project!*

