@echo off
setlocal
cd /d "%~dp0"

set RISCV_PREFIX=riscv64-unknown-elf-

echo [1] Building FreeRTOS firmware -^> prog.elf...
%RISCV_PREFIX%gcc ^
  -march=rv32i_zicsr -mabi=ilp32 -mno-relax ^
  -ffreestanding -nostdlib -nostartfiles ^
  -I freertos_kernel/include ^
  -I freertos_port ^
  -T link.ld ^
  crt0.s ^
  uart.c ^
  main.c ^
  mem_util.c ^
  freertos_kernel/event_groups.c ^
  freertos_kernel/list.c ^
  freertos_kernel/queue.c ^
  freertos_kernel/stream_buffer.c ^
  freertos_kernel/tasks.c ^
  freertos_kernel/timers.c ^
  freertos_port/port.c ^
  freertos_port/portASM.s ^
  freertos_port/heap_4.c ^
  -lgcc -o prog.elf

if errorlevel 1 (
    echo ERROR: Compilation failed!
    exit /b 1
)

echo [2] ELF -^> BIN...
%RISCV_PREFIX%objcopy -O binary prog.elf prog.bin

echo [3] BIN -^> HEX...
python make_hex.py

echo [4] Copying instr_mem.vh to Vivado directories...
copy /Y instr_mem.vh ..\instr_mem.vh
copy /Y instr_mem.vh ..\FPGA_CPU1.runs\synth_1\instr_mem.vh 2>nul
copy /Y instr_mem.vh ..\FPGA_CPU1.ip_user_files\mem_init_files\instr_mem.vh 2>nul
copy /Y instr_mem.vh ..\FPGA_CPU1.sim\sim_1\behav\xsim\instr_mem.vh 2>nul
copy /Y instr_mem.vh ..\sim_debug\instr_mem.vh 2>nul

echo.
echo ============================================
echo    FreeRTOS firmware build complete!
echo ============================================
echo.
echo IMPORTANT: In Vivado, you MUST:
echo   1. Right-click 'synth_1' -^> 'Reset Synthesis'
echo   2. Re-run Synthesis -^> Implementation -^> Generate Bitstream
echo   3. The memory contents are baked into the bitstream!
echo.

