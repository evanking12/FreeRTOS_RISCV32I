# 🐛 Bug Documentation

Detailed documentation of 14 bugs encountered and fixed while porting FreeRTOS to a custom RISC-V CPU. These represent real hardware-software integration challenges that required understanding both domains simultaneously.

---

## Hardware Bugs (Verilog)

### Bug #1: mret Return Address +4
**File:** `cpu_core.v`  
**Severity:** Critical  

**Symptom:** After `mret`, CPU jumped to `mepc + 4` instead of `mepc`

**Root Cause:** Branch target calculation incorrectly added 4:
```verilog
// BROKEN:
assign branch_target_mret = csr_mepc + 32'd4;

// FIXED:
assign branch_target_mret = csr_mepc;
```

**Why:** `mret` should return to the exact address in `mepc`. The +4 was left over from exception handling logic where we skip the faulting instruction.

---

### Bug #2: Interrupt mepc Save Bug
**File:** `cpu_core.v`  
**Severity:** Critical  

**Symptom:** After interrupt, CPU resumed at wrong instruction (skipped one)

**Root Cause:** Saved decode-stage PC instead of fetch-stage PC:
```verilog
// BROKEN: Saved the wrong PC
csr_mepc <= id_pc;  // Decode stage - instruction already moved past!

// FIXED: Save the instruction about to execute
csr_mepc <= pc;     // Fetch stage PC - correct!
```

**Why:** When interrupt fires, we want to return to the instruction that was *about* to execute, not the one currently being decoded.

---

### Bug #3: CSR Write Priority Conflict
**File:** `cpu_core.v`  
**Severity:** Critical  

**Symptom:** `mstatus.MIE` stayed 0 after `mret` - interrupts never re-enabled

**Root Cause:** Two independent `if` blocks could both execute on same cycle:
```verilog
// BROKEN: Both could fire on mret cycle!
if (is_mret) begin
    csr_mstatus[3] <= csr_mstatus_mpie;  // MIE <= MPIE
end
if (mem_is_csr && csr_instr_write) begin
    csr_mstatus <= csr_instr_wdata;      // Overwrites mret's update!
end

// FIXED: Made mutually exclusive
if (is_mret) begin
    csr_mstatus[3] <= csr_mstatus_mpie;
end else if (mem_is_csr && csr_instr_write) begin
    csr_mstatus <= csr_instr_wdata;
end
```

**Why:** In Verilog, independent `if` blocks in same `always` block can all execute. The second one was overwriting the first.

---

### Bug #4: Interrupts During System Operations
**File:** `cpu_core.v`  
**Severity:** Critical  

**Symptom:** Timer interrupt during `mret` corrupted mepc, causing system crash

**Root Cause:** No blocking of interrupts during privileged instructions

**Fix:**
```verilog
wire system_op_in_pipeline = ex_is_csr | is_ecall | is_ebreak | is_mret;

wire irq_take = timer_irq && csr_mstatus_mie && csr_mie_mtie 
                && !system_op_in_pipeline;  // Block during system ops!
```

**Why:** Taking an interrupt in the middle of `mret` would overwrite mepc before the return completed.

---

### Bug #5: Register Writeback Not Cancelled on Trap
**File:** `cpu_core.v`  
**Severity:** High  

**Symptom:** Wrong values written to registers when trap flushed pipeline

**Fix:** Added `trap_wb_cancel` signal to block writebacks during trap flush cycle.

**Why:** Instructions in flight when trap occurs should not complete their writeback.

---

### Bug #6: Memory Writes Not Cancelled on Trap
**File:** `cpu_core.v`  
**Severity:** High  

**Symptom:** Spurious stores to memory during trap handling

**Fix:** Added `!trap_wb_cancel` condition to data memory write enable.

**Why:** Same as above - stores in flight should be cancelled when trap flushes pipeline.

---

### Bug #7: Reset Synchronization (mtvec = 0x00000004)
**File:** `pc_reg.v`  
**Severity:** Critical  

**Symptom:** `mtvec` showed `0x00000004` instead of `0x00000130` on first boot

**Root Cause:** Synchronous reset - PC started executing while other registers still in reset:
```verilog
// BROKEN (synchronous reset):
always @(posedge clk) begin
    if (!rst_n) pc <= 32'h0;
end

// FIXED (asynchronous reset):
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) pc <= 32'h0;
end
```

**Why:** With synchronous reset, PC was already at 0x04 when the `auipc` instruction executed to set up mtvec, capturing wrong value.

---

### Bug #8: Instruction Fetch Timing
**File:** `cpu_top.v`  
**Severity:** High  

**Symptom:** CPU executed garbage before instruction memory was ready

**Fix:** Changed step signal to wait for `instr_ready`:
```verilog
wire step_pulse = instr_ready;  // Don't step until memory ready
```

---

### Bug #9: Critical Nesting Pointer Undefined
**File:** `port.c`  
**Severity:** Critical  

**Symptom:** System crashed after ~5000 context switches with memory corruption

**Root Cause:** Assembly code referenced `pxCriticalNesting` but it was never defined:
```c
// MISSING - assembly expected this to exist!
size_t *pxCriticalNesting = &xCriticalNesting;
```

**Why:** Every context restore wrote the critical nesting count through an undefined pointer, corrupting random memory. Took thousands of iterations to hit something important.

---

## Firmware Bugs (Assembly/C)

### Bug #10: Interrupts Enabled Too Early
**File:** `portASM.S`  
**Severity:** Critical  

**Symptom:** Interrupt fired during register restore, corrupted task state

**Root Cause:** Set `MIE=1` before `mret`:
```asm
# BROKEN:
li t1, (1 << 3) | (3 << 11)   # MIE=1 - interrupts enabled NOW!
csrw mstatus, t1
# ...restore registers... (INTERRUPT CAN FIRE HERE!)
mret

# FIXED:
li t1, (1 << 7) | (3 << 11)   # MPIE=1, MIE=0
csrw mstatus, t1
# ...restore registers... (safe - interrupts disabled)
mret                           # mret atomically sets MIE=MPIE
```

**Why:** `mret` atomically restores MIE from MPIE. Setting MIE=1 manually before mret creates a window for interrupts.

---

### Bug #11: MPIE Not Set in trap_exit
**File:** `portASM.S`  
**Severity:** High  

**Symptom:** Interrupts never re-enabled after first trap

**Fix:** Added explicit `csrw mstatus` with `MPIE=1` before `mret`.

---

### Bug #12: Debug Prints Polluting Output
**Files:** `crt0.s`, `portASM.S`  
**Severity:** Low  

**Symptom:** `[MTVEC=...]` and `[MEPC=...]` mixed with task output

**Fix:** Removed debug prints for clean demo.

---

### Bug #13: UART Corruption from Concurrent Tasks
**File:** `main.c`  
**Severity:** Medium  

**Symptom:** Garbled output, `0x▒▒▒▒` characters

**Root Cause:** Context switch mid-print, two tasks writing UART simultaneously

**Fix:**
```c
taskENTER_CRITICAL();
uart_puts("[A] ");
print_num(count++);
uart_puts("\r\n");
taskEXIT_CRITICAL();
```

---

### Bug #14: Local Variables Not Persisting
**File:** `main.c`  
**Severity:** Medium  

**Symptom:** Task counters stuck at same value or behaving erratically

**Root Cause:** Stack-allocated counters could be corrupted or not properly saved

**Fix:** Made counters global `volatile` instead of `static` local.

---

## Interview Talking Points

**Top 5 bugs to discuss:**

1. **Reset Sync** - "mtvec was wrong because pipeline stages exited reset at different times - classic async vs sync reset issue"

2. **CSR Priority** - "Two Verilog if-blocks both firing on same cycle, required understanding hardware parallelism"

3. **IRQ Blocking** - "Added system_op_in_pipeline to block interrupts during mret - race condition in hardware"

4. **Critical Pointer** - "Undefined symbol in assembly caused random memory corruption after thousands of iterations"

5. **mret Atomicity** - "Had to understand that mret atomically restores MIE from MPIE, can't manually enable interrupts before"



