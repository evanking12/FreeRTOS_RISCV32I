@echo off
REM BUILD DEBUG TESTS - Windows Version
REM Usage:
REM   build_debug.bat trap_test       - Build standalone trap test
REM   build_debug.bat context_test    - Build context switch test  
REM   build_debug.bat freertos        - Build FreeRTOS (normal)

cd /d "%~dp0"

set TEST=%1
if "%TEST%"=="" set TEST=trap_test

echo ================================================
echo   Building: %TEST%
echo ================================================

REM Use MSYS2 to run the shell script
C:\msys64\msys2_shell.cmd -mingw64 -defterm -no-start -here -c "./build_debug.sh %TEST%"

