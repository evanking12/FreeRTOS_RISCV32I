@echo off
REM Quick Debug Simulation Runner
REM Run from sim_debug directory

cd /d "%~dp0"

echo ================================================
echo   Running Debug Simulation
echo ================================================
echo.

REM Check if compiled testbench exists
if not exist xsim.dir\tb_cpu_behav\xsimk.dll (
    echo Need to compile testbench first...
    echo Run this in Vivado TCL console:
    echo   cd sim_debug
    echo   xvlog -f files.f -sv
    echo   xelab -top tb_cpu -snapshot tb_cpu_behav
    echo.
    pause
    exit /b 1
)

echo Running 50ms simulation...
echo.
xsim tb_cpu_behav -t tb_cpu_fast.tcl -log simulate.log

echo.
echo ================================================
echo   Simulation complete - check simulate.log
echo ================================================
pause

