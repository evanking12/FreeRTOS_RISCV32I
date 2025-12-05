@echo off
setlocal
cd /d "%~dp0"

echo ================================================
echo   Firmware Simulation (runs actual firmware)
echo ================================================
echo.

REM First, make sure firmware is built
echo [1] Ensuring firmware is up to date...
cd firmware
call build.bat
if errorlevel 1 (
    echo ERROR: Firmware build failed!
    exit /b 1
)
cd ..

echo.
echo [2] Compiling simulation...
iverilog -g2012 -o sim_firmware ^
    firmware_sim_tb.sv ^
    FPGA_CPU1.srcs/sources_1/new/cpu_top.v ^
    FPGA_CPU1.srcs/sources_1/new/cpu_core.v ^
    FPGA_CPU1.srcs/sources_1/new/id_ex.v ^
    FPGA_CPU1.srcs/sources_1/new/if_id.v ^
    FPGA_CPU1.srcs/sources_1/new/decoder.v ^
    FPGA_CPU1.srcs/sources_1/new/alu.v ^
    FPGA_CPU1.srcs/sources_1/new/regfile.v ^
    FPGA_CPU1.srcs/sources_1/new/pc_reg.v ^
    FPGA_CPU1.srcs/sources_1/new/pc_stepper.v ^
    FPGA_CPU1.srcs/sources_1/new/uart_tx.v ^
    FPGA_CPU1.srcs/sources_1/new/uart_rx.v

if errorlevel 1 (
    echo ERROR: Compilation failed!
    exit /b 1
)

echo.
echo [3] Running simulation (will show UART output and detect restarts)...
echo ================================================
vvp sim_firmware

echo.
echo ================================================
echo   Simulation complete!
echo ================================================

