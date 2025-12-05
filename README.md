# FreeRTOS on Custom RISC-V CPU

A custom 3-stage pipelined RISC-V (RV32I) CPU implemented in Verilog, running FreeRTOS real-time operating system on FPGA.

![Status](https://img.shields.io/badge/status-working-brightgreen)
![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-blue)
![RTOS](https://img.shields.io/badge/RTOS-FreeRTOS%20v10.5.1-orange)

## 🎯 Project Overview

This project demonstrates a complete hardware-software system:
- **Custom CPU**: 3-stage pipelined RV32I RISC-V core
- **RTOS**: FreeRTOS ported to run on the custom hardware
- **FPGA**: Synthesized and tested on Xilinx Artix-7

### Demo Output
```
╔═══════════════════════════════════════════════════════╗
║   ███████╗██████╗ ███████╗███████╗██████╗ ████████╗   ║
║   ██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗╚══██╔══╝   ║
║   █████╗  ██████╔╝█████╗  █████╗  ██████╔╝   ██║      ║
║   ██╔══╝  ██╔══██╗██╔══╝  ██╔══╝  ██╔══██╗   ██║      ║
║   ██║     ██║  ██║███████╗███████╗██║  ██║   ██║      ║
║   ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝      ║
║          on Custom RISC-V CPU (RV32I)                 ║
╚═══════════════════════════════════════════════════════╝

[A] #4520
[B] #4521
[C] #4522
[A] #4523
...
```

## 🏗️ Architecture

### CPU Pipeline (3-Stage)
```
┌─────────┐    ┌─────────────┐    ┌─────────────┐
│   IF    │───▶│   ID/EX     │───▶│   MEM/WB    │
│ (Fetch) │    │(Decode+Exec)│    │(Mem+Write)  │
└─────────┘    └─────────────┘    └─────────────┘
```

### Features
- **ISA**: RV32I base integer instruction set
- **CSRs**: mstatus, mie, mip, mtvec, mepc, mcause
- **Traps**: ecall, mret, timer interrupts
- **Memory**: 128KB instruction + data memory
- **Peripherals**: UART TX/RX, GPIO LEDs, Machine Timer

## 📁 Project Structure

```
FPGA_CPU1/
├── FPGA_CPU1.srcs/sources_1/new/    # RTL Source Files
│   ├── cpu_core.v                   # Main CPU pipeline
│   ├── cpu_top.v                    # Top-level with memory
│   ├── pc_reg.v                     # Program counter
│   ├── decoder.v                    # Instruction decoder
│   ├── alu.v                        # Arithmetic logic unit
│   ├── regfile.v                    # Register file
│   ├── uart_tx.v                    # UART transmitter
│   ├── uart_rx.v                    # UART receiver
│   └── top.v                        # FPGA top module
│
├── firmware/                        # Software
│   ├── main.c                       # FreeRTOS demo application
│   ├── crt0.s                       # Startup assembly
│   ├── uart.c/h                     # UART driver
│   ├── link.ld                      # Linker script
│   ├── build_debug.sh               # Build script
│   │
│   ├── freertos_kernel/             # FreeRTOS kernel source
│   │   ├── tasks.c
│   │   ├── queue.c
│   │   ├── list.c
│   │   └── ...
│   │
│   └── freertos_port/               # Custom RISC-V port
│       ├── port.c                   # Port C functions
│       ├── portASM.S                # Context switch assembly
│       ├── portmacro.h              # Port macros
│       └── FreeRTOSConfig.h         # RTOS configuration
│
└── FPGA_CPU1.xpr                    # Vivado project file
```

## 🔧 Building

### Prerequisites
- Xilinx Vivado 2024.x or later
- RISC-V GCC toolchain (`riscv64-unknown-elf-gcc`)
- MSYS2 (Windows) or native Linux

### Build Firmware
```bash
cd firmware
./build_debug.sh freertos
```

### Build FPGA Bitstream
1. Open `FPGA_CPU1.xpr` in Vivado
2. Run Synthesis
3. Run Implementation
4. Generate Bitstream
5. Program FPGA

## 🐛 Bugs Fixed During Development

This project required debugging 13 hardware and firmware bugs:

| Bug | Description | Fix |
|-----|-------------|-----|
| mret +4 | CPU jumped to mepc+4 instead of mepc | Fixed branch target calculation |
| mepc save | Wrong PC saved on interrupt | Save fetch-stage PC, not decode-stage |
| CSR conflict | mret's MIE update overwritten | Changed `if` to `else if` for mutual exclusion |
| IRQ timing | Interrupt during mret corrupted state | Block interrupts during system operations |
| Reset sync | mtvec=0x04 on boot | Changed to async reset |
| Pipeline flush | Writes not cancelled on trap | Added trap_wb_cancel signal |
| MPIE restore | Interrupts never re-enabled | Set MPIE=1 before mret |

See [BUGS.md](BUGS.md) for detailed writeups.

## 📊 Resource Utilization

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | ~2,500 | 20,800 | 12% |
| FFs | ~1,200 | 41,600 | 3% |
| BRAM | 8 | 50 | 16% |

## 🎓 Skills Demonstrated

- **Digital Design**: Verilog HDL, pipelining, hazard detection
- **Computer Architecture**: RISC-V ISA, CSRs, trap handling
- **Embedded Systems**: RTOS internals, context switching, interrupt handling
- **Hardware-Software Co-Design**: Debugging across hardware/firmware boundary
- **FPGA Development**: Synthesis, timing closure, on-chip debugging

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

##  Acknowledgments

- FreeRTOS project for the kernel
- RISC-V Foundation for the ISA specification

