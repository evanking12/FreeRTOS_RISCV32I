# FreeRTOS on Custom RISC-V CPU

**A 3-stage pipelined RISC-V processor running FreeRTOS with 13,000+ demonstrated context switches on FPGA hardware.**

![Demo](assets/demo.gif)

**[📺 Watch Full Demo on YouTube](https://youtube.com/shorts/Ne9sMYk7_0U)**

> 🎥 *Three FreeRTOS tasks context-switching on custom RISC-V silicon*

---

## 🎯 What This Is

A complete **hardware + software** system built from scratch:
- **Custom CPU**: 3-stage pipelined RV32I RISC-V core written in Verilog
- **Real-Time OS**: FreeRTOS v10.5.1 ported to run on the custom hardware
- **Working Hardware**: Synthesized and tested on Xilinx Artix-7 FPGA

This isn't a tutorial project with pre-built components—every line of RTL and every assembly instruction in the port was written and debugged by hand.

---

## 📊 Demo Results

| Metric | Result |
|--------|--------|
| Context switches tested | **13,000+** |
| Concurrent tasks | 3 |
| CPU frequency | 25 MHz |
| Platform | Arty A7-100T FPGA |
| Bugs debugged | 14 hardware/software issues |
| Video proof | [YouTube Demo](https://youtube.com/shorts/Ne9sMYk7_0U) |

### Terminal Output
```
========================================
  FreeRTOS on Custom RISC-V CPU
========================================
  CPU:  3-stage pipeline @ 25MHz
  ISA:  RISC-V RV32I
  RTOS: FreeRTOS v10.5.1
========================================

Starting 3 tasks...

[A] 0
[B] 0
[C] 0
[A] 1
[B] 1
[C] 1
[A] 2
...
```

---

## 🏗️ Architecture

### CPU Pipeline (3-Stage)
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│     IF      │───▶│   ID/EX     │───▶│   MEM/WB    │
│   (Fetch)   │    │(Decode+Exec)│    │(Memory+WB)  │
└─────────────┘    └─────────────┘    └─────────────┘
```

### Hardware Features
- **ISA**: RV32I base integer instruction set
- **CSRs**: mstatus, mie, mip, mtvec, mepc, mcause
- **Traps**: ecall, mret, timer interrupts
- **Memory**: 128KB unified instruction/data
- **Peripherals**: UART TX/RX, GPIO LEDs, Machine Timer (CLINT)

### Software Stack
```
┌─────────────────────────────────┐
│     Application (main.c)        │  ← 3 demo tasks
├─────────────────────────────────┤
│     FreeRTOS Kernel             │  ← Scheduler, queues, tasks
├─────────────────────────────────┤
│     Custom RISC-V Port          │  ← Context switch, trap handler
├─────────────────────────────────┤
│     Custom CPU Hardware         │  ← Verilog RTL
└─────────────────────────────────┘
```

---

## 🐛 Critical Bugs Debugged (14 Total)

Getting FreeRTOS stable required systematic debugging across the hardware-software boundary:

### Hardware Bugs (9)
| Bug | Description | Impact |
|-----|-------------|--------|
| mret +4 | CPU jumped to `mepc+4` instead of `mepc` | Tasks resumed at wrong instruction |
| mepc save | Saved decode-stage PC instead of fetch-stage | Interrupt return corrupted |
| CSR priority | Two `if` blocks both writing mstatus | mret's MIE update overwritten |
| IRQ blocking | Interrupt during mret corrupted state | System crash |
| WB cancel | Register writes not cancelled on trap | Wrong values in registers |
| MEM cancel | Memory writes not cancelled on trap | Memory corruption |
| Reset sync | Synchronous reset caused mtvec=0x04 | Traps jumped to wrong handler |
| Fetch timing | CPU executed before memory ready | Garbage instructions |
| Critical ptr | `pxCriticalNesting` never defined | Random memory corruption |

### Firmware Bugs (5)
| Bug | Description | Impact |
|-----|-------------|--------|
| Early IRQ | Set MIE=1 before mret | Interrupt during register restore |
| MPIE restore | MPIE not set before mret | Interrupts never re-enabled |
| Debug prints | Leftover prints in boot code | Polluted output |
| UART race | Tasks printing simultaneously | Garbled characters |
| Stack vars | Local counters not persisting | State lost on context switch |

**[📄 Full Bug Documentation →](docs/BUGS.md)**

---

## 📁 Project Structure

```
FreeRTOS_RISCV32I/
├── README.md
├── LICENSE
├── .gitignore
│
├── rtl/                          # Verilog RTL
│   ├── cpu_core.v                # Main CPU pipeline + CSRs
│   ├── cpu_top.v                 # Top-level with memory
│   ├── pc_reg.v                  # Program counter
│   ├── alu.v                     # Arithmetic logic unit
│   ├── regfile.v                 # Register file
│   ├── decoder.v                 # Instruction decoder
│   ├── uart_tx.v / uart_rx.v     # UART peripheral
│   └── top.v                     # FPGA top module
│
├── firmware/                     # Software
│   ├── main.c                    # FreeRTOS demo application
│   ├── crt0.s                    # Startup assembly
│   ├── uart.c / uart.h           # UART driver
│   ├── link.ld                   # Linker script
│   ├── build_debug.sh            # Build script
│   │
│   ├── freertos_kernel/          # FreeRTOS source
│   │   ├── tasks.c
│   │   ├── queue.c
│   │   └── ...
│   │
│   └── freertos_port/            # Custom RISC-V port
│       ├── port.c                # Port C functions
│       ├── portASM.S             # Context switch assembly
│       ├── portmacro.h           # Port macros
│       └── FreeRTOSConfig.h      # RTOS configuration
│
├── sim/                          # Simulation testbenches
│
├── docs/                         # Documentation
│   └── BUGS.md                   # Detailed bug writeups
│
└── assets/                       # Demo media
    └── demo.gif
```

---

## 🚀 Quick Start

### Prerequisites
- RISC-V GCC toolchain (`riscv64-unknown-elf-gcc`)
- Xilinx Vivado 2024.x (for FPGA synthesis)
- UART terminal (PuTTY, minicom, etc.)

### Build Firmware
```bash
cd firmware
./build_debug.sh freertos
```

### Run Simulation
```bash
cd sim_debug
xsim tb_cpu_behav -t tb_cpu_fast.tcl
```

### Program FPGA
1. Open Vivado project (`FPGA_CPU1.xpr`)
2. Generate bitstream
3. Program device
4. Connect UART at 115200 baud

---

## 🎓 Skills Demonstrated

| Category | Skills |
|----------|--------|
| **Digital Design** | Verilog HDL, pipelining, hazard detection, FSMs |
| **Computer Architecture** | RISC-V ISA, CSRs, trap handling, interrupts |
| **Embedded Systems** | RTOS internals, context switching, critical sections |
| **Hardware-Software Co-Design** | Cross-boundary debugging, timing analysis |
| **FPGA Development** | Synthesis, timing closure, on-chip debugging |

---

## 📈 Resource Utilization (Artix-7 100T)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | ~2,500 | 63,400 | 4% |
| FFs | ~1,200 | 126,800 | 1% |
| BRAM | 8 | 135 | 6% |

---

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- [FreeRTOS](https://freertos.org/) for the kernel
- [RISC-V Foundation](https://riscv.org/) for the open ISA specification
