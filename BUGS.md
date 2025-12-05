# Bug Hall of Fame 🐛

Detailed documentation of bugs encountered and fixed while porting FreeRTOS to a custom RISC-V CPU.

---

## Hardware Bugs (Verilog)

### Bug #1: mret Return Address +4
**File:** `cpu_core.v`

**Symptom:** After `mret`, CPU jumped to `mepc + 4` instead of `mepc`

**Root Cause:** Branch target calculation was wrong:
```verilog
// BROKEN:
assign branch_target_mret = csr_mepc + 32'd4;

// FIXED:
assign branch_target_mret = csr_mepc;
```

**Why:** `mret` should return to the exact address in `mepc`, not skip an instruction.

---

### Bug #2: Interrupt mepc Save Bug
**File:** `cpu_core.v`

**Symptom:** After interrupt, CPU resumed at wrong instruction

**Root Cause:** Saved decode-stage PC instead of fetch-stage PC:
```verilog
// BROKEN: Saved the wrong PC
csr_mepc <= id_pc;  // Decode stage - already moved past!

// FIXED: Save the instruction that was about to execute
csr_mepc <= pc;     // Fetch stage - correct!
```

---

### Bug #3: mret vs CSR Write Priority Conflict
**File:** `cpu_core.v`

**Symptom:** `mstatus.MIE` stayed 0 after `mret` - interrupts never re-enabled

**Root Cause:** Two `if` blocks could both execute on same cycle:
```verilog
// BROKEN: Both could fire!
if (is_mret) begin
    csr_mstatus[3] <= csr_mstatus_mpie;  // MIE <= MPIE
end
if (mem_is_csr && csr_instr_write) begin
    csr_mstatus <= csr_instr_wdata;      // Overwrites!
end

// FIXED: Mutually exclusive
if (is_mret) begin
    csr_mstatus[3] <= csr_mstatus_mpie;
end else if (mem_is_csr && csr_instr_write) begin
    csr_mstatus <= csr_instr_wdata;
end
```

---

### Bug #4: Interrupts During System Operations
**File:** `cpu_core.v`

**Symptom:** Timer interrupt during `mret` corrupted mepc, system crashed

**Root Cause:** No blocking of interrupts during privileged instructions

**Fix:**
```verilog
wire system_op_in_pipeline = ex_is_csr | is_ecall | is_ebreak | is_mret;

wire irq_take = timer_irq && csr_mstatus_mie && csr_mie_mtie 
                && !system_op_in_pipeline;  // Block during system ops!
```

---

### Bug #5: Register Writeback Not Cancelled on Trap
**File:** `cpu_core.v`

**Symptom:** Wrong values written to registers when trap flushed pipeline

**Fix:** Added `trap_wb_cancel` signal to block writebacks during trap flush.

---

### Bug #6: Memory Writes Not Cancelled on Trap
**File:** `cpu_core.v`

**Symptom:** Spurious stores to memory during trap handling

**Fix:** Added `!trap_wb_cancel` to data write enable signal.

---

### Bug #7: Reset Synchronization (mtvec = 0x00000004)
**File:** `pc_reg.v`

**Symptom:** `mtvec` showed `0x00000004` instead of `0x00000130` on boot

**Root Cause:** Synchronous reset - PC executed instruction at address 0 on the same cycle reset was released. The `auipc` instruction captured `id_pc = 4` instead of `0`.

**Fix:**
```verilog
// BROKEN (synchronous):
always @(posedge clk) begin
    if (!rst_n) pc <= 32'h0;
end

// FIXED (asynchronous):
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) pc <= 32'h0;
end
```

---

### Bug #8: Instruction Fetch Timing
**File:** `cpu_top.v`

**Symptom:** CPU executed garbage before instruction memory was ready

**Fix:** Changed step signal to wait for `instr_ready`.

---

## Firmware Bugs (Assembly)

### Bug #9: Interrupts Enabled Too Early
**File:** `portASM.S`

**Symptom:** Interrupt fired during register restore, corrupted task state

**Root Cause:** Set `MIE=1` before `mret`:
```asm
# BROKEN:
li t1, (1 << 3) | (3 << 11)   # MIE=1 - interrupts enabled NOW!
csrw mstatus, t1
# ...restore registers... (INTERRUPT FIRES HERE!)
mret

# FIXED:
li t1, (1 << 7) | (3 << 11)   # MPIE=1, MIE=0
csrw mstatus, t1
# ...restore registers... (safe - interrupts disabled)
mret                           # mret atomically sets MIE=MPIE=1
```

---

### Bug #10: MPIE Not Set in trap_exit
**File:** `portASM.S`

**Symptom:** Interrupts never re-enabled after first trap

**Fix:** Added explicit `csrw mstatus` with `MPIE=1` before `mret`.

---

## Firmware Bugs (C Code)

### Bug #11: Debug Prints Polluting Output
**Files:** `crt0.s`, `portASM.S`

**Symptom:** `[MTVEC=...]` and `[MEPC=...]` mixed with task output

**Fix:** Removed debug prints for clean demo.

---

### Bug #12: UART Corruption from Concurrent Tasks
**File:** `main.c`

**Symptom:** Garbled output, `0x▒▒▒▒` characters

**Root Cause:** Context switch mid-print, two tasks writing UART simultaneously

**Fix:**
```c
taskENTER_CRITICAL();
uart_puts("[A] #");
print_num(count++);
uart_puts("\r\n");
taskEXIT_CRITICAL();
```

---

### Bug #13: Local Variables Not Persisting
**File:** `main.c`

**Symptom:** Task counters stuck at same value

**Fix:** Made counters `static` instead of stack-allocated.

---

## Interview Cheat Sheet

**Top 5 bugs to talk about:**

1. **Reset Sync** - "mtvec was wrong because pipeline stages exited reset at different times"
2. **mret Priority** - "Timer interrupt during mret corrupted the return address"
3. **CSR Conflict** - "Two if-blocks both writing mstatus on same cycle"
4. **IRQ Blocking** - "Added system_op_in_pipeline to block interrupts during mret"
5. **UART Race** - "Tasks printing simultaneously, fixed with critical sections"

**One-liner for resume:**
> "Debugged 13 hardware-software integration bugs including reset synchronization, interrupt priority conflicts, and context save/restore timing errors"

