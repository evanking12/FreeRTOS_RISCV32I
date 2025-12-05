# Run Simulation Script for FreeRTOS Debug Tests
# Run this from PowerShell after setting Vivado environment

param(
    [int]$TimeMs = 50,
    [switch]$Recompile
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  FreeRTOS Debug Simulation Runner" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check if we need to set Vivado environment
if (-not (Get-Command "xsim" -ErrorAction SilentlyContinue)) {
    Write-Host "Vivado not in PATH. Looking for settings64.bat..." -ForegroundColor Yellow
    
    # Common Vivado locations
    $vivadoPaths = @(
        "C:\Xilinx\Vivado\2025.2\settings64.bat",
        "C:\Xilinx\Vivado\2024.2\settings64.bat",
        "C:\Xilinx\Vivado\2024.1\settings64.bat",
        "D:\Xilinx\Vivado\2025.2\settings64.bat",
        "$env:USERPROFILE\Xilinx\Vivado\2025.2\settings64.bat"
    )
    
    foreach ($path in $vivadoPaths) {
        if (Test-Path $path) {
            Write-Host "Found Vivado at: $path" -ForegroundColor Green
            Write-Host "Please run this command first to setup environment:"
            Write-Host "  & `"$path`"" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Or run simulation from Vivado TCL console:" -ForegroundColor Yellow
            Write-Host "  cd C:/Users/evanw/FPGA_CPU1/sim_debug"
            Write-Host "  xsim tb_cpu_behav -t tb_cpu_fast.tcl"
            exit 0
        }
    }
    
    Write-Host "Could not find Vivado. Please run simulation from Vivado IDE." -ForegroundColor Red
    exit 1
}

Set-Location $PSScriptRoot

# Recompile if requested or if snapshot doesn't exist
if ($Recompile -or -not (Test-Path "xsim.dir\tb_cpu_behav")) {
    Write-Host "Compiling testbench..." -ForegroundColor Yellow
    
    # Compile sources
    xvlog -f files.f -sv 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Compilation failed!" -ForegroundColor Red
        exit 1
    }
    
    # Elaborate
    xelab -top tb_cpu -snapshot tb_cpu_behav 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Elaboration failed!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Compilation successful!" -ForegroundColor Green
}

# Create a TCL script for the specified runtime
$tclContent = @"
run ${TimeMs}ms
puts ""
puts "=== Simulation complete (${TimeMs}ms) ==="
quit
"@

$tclContent | Out-File -FilePath "run_temp.tcl" -Encoding ASCII

# Run simulation
Write-Host "Running simulation for ${TimeMs}ms..." -ForegroundColor Cyan
Write-Host ""

xsim tb_cpu_behav -t run_temp.tcl -log simulate.log

# Cleanup
Remove-Item "run_temp.tcl" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Simulation complete - output in simulate.log" -ForegroundColor Cyan  
Write-Host "================================================" -ForegroundColor Cyan

