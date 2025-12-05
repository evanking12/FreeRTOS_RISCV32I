`timescale 1ns/1ps

/*
 * ENHANCED DEBUG TESTBENCH
 * Provides detailed trap/interrupt diagnostics for debugging FreeRTOS
 */
module tb_cpu_debug;
  reg clk100_raw = 0;
  reg rst_n = 0;
  reg btn0 = 0;
  reg [1:0] sw = 2'b00;
  wire [3:0] led;
  wire uart_tx;
  reg uart_rx = 1'b1;

  // Clock divider: 100MHz -> 25MHz
  reg [1:0] clk_div = 0;
  always @(posedge clk100_raw) clk_div <= clk_div + 1;
  wire clk25 = clk_div[1];

  cpu_top dut (
    .clk100(clk25),
    .rst_n(rst_n),
    .btn0(btn0),
    .sw(sw),
    .led(led),
    .uart_tx(uart_tx),
    .uart_rx(uart_rx)
  );

  always #5 clk100_raw = ~clk100_raw; // 100 MHz base clock

  // UART capture
  reg [7:0] rx_mem [0:4095];
  integer rx_count = 0;

  // PC tracking
  reg [31:0] last_pc = 0;
  wire [31:0] current_pc = dut.pc;
  integer restart_count = 0;
  
  // CSR tracking
  reg [31:0] last_mtvec = 0;
  reg [31:0] last_mepc = 0;
  reg [31:0] last_mcause = 0;
  reg [31:0] last_mstatus = 0;
  integer trap_count = 0;
  integer ecall_count = 0;
  integer timer_int_count = 0;
  
  // Stack pointer tracking
  reg [31:0] last_sp = 0;
  wire [31:0] current_sp = dut.u_cpu.regfile_inst.regs[2]; // x2 = sp
  
  // Detect and log all events
  always @(posedge clk25) begin
    if (rst_n) begin
      // ============================================================
      // RESTART DETECTION (PC jumps to 0)
      // ============================================================
      if (current_pc == 32'h00000000 && last_pc != 32'h00000000 && last_pc !== 32'hxxxxxxxx) begin
        restart_count = restart_count + 1;
        $display("");
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("!!! RESTART #%0d at time %0t", restart_count, $time);
        $display("!!! PC: 0x%08h -> 0x00000000", last_pc);
        $display("!!! SP: 0x%08h", current_sp);
        $display("!!! mtvec:   0x%08h", dut.u_cpu.csr_mtvec);
        $display("!!! mstatus: 0x%08h", dut.u_cpu.csr_mstatus);
        $display("!!! mepc:    0x%08h", dut.u_cpu.csr_mepc);
        $display("!!! mcause:  0x%08h", dut.u_cpu.csr_mcause);
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("");
        
        if (restart_count >= 2) begin
          $display("*** Stopping after 2 restarts ***");
          $finish;
        end
      end
      
      // ============================================================
      // TRAP DETECTION (mepc changes = new trap occurred)
      // ============================================================
      if (dut.u_cpu.csr_mepc != last_mepc && dut.u_cpu.csr_mepc != 0) begin
        trap_count = trap_count + 1;
        
        if (dut.u_cpu.csr_mcause[31]) begin
          // INTERRUPT
          timer_int_count = timer_int_count + 1;
          if (timer_int_count <= 5) begin
            $display("[INT #%0d] Timer at t=%0t", timer_int_count, $time);
            $display("          mepc=0x%08h mcause=0x%08h", 
                     dut.u_cpu.csr_mepc, dut.u_cpu.csr_mcause);
            $display("          SP=0x%08h PC=0x%08h", current_sp, current_pc);
          end
        end else begin
          // EXCEPTION
          if (dut.u_cpu.csr_mcause == 32'hB) begin
            ecall_count = ecall_count + 1;
            if (ecall_count <= 10) begin
              $display("[ECALL #%0d] at t=%0t", ecall_count, $time);
              $display("            mepc=0x%08h SP=0x%08h", 
                       dut.u_cpu.csr_mepc, current_sp);
            end
          end else begin
            $display("");
            $display("!!! EXCEPTION at t=%0t !!!", $time);
            $display("!!! mcause=0x%08h mepc=0x%08h", 
                     dut.u_cpu.csr_mcause, dut.u_cpu.csr_mepc);
            case (dut.u_cpu.csr_mcause)
              32'h0: $display("    Cause: Instruction address misaligned");
              32'h1: $display("    Cause: Instruction access fault");
              32'h2: $display("    Cause: Illegal instruction");
              32'h3: $display("    Cause: Breakpoint (ebreak)");
              32'h4: $display("    Cause: Load address misaligned");
              32'h5: $display("    Cause: Load access fault");
              32'h6: $display("    Cause: Store address misaligned");
              32'h7: $display("    Cause: Store access fault");
              default: $display("    Cause: Unknown (%0d)", dut.u_cpu.csr_mcause);
            endcase
            $display("");
          end
        end
        last_mepc <= dut.u_cpu.csr_mepc;
        last_mcause <= dut.u_cpu.csr_mcause;
      end
      
      // ============================================================
      // MTVEC CHANGE DETECTION
      // ============================================================
      if (dut.u_cpu.csr_mtvec != last_mtvec) begin
        $display("[MTVEC] Changed: 0x%08h -> 0x%08h at t=%0t", 
                 last_mtvec, dut.u_cpu.csr_mtvec, $time);
        last_mtvec <= dut.u_cpu.csr_mtvec;
      end
      
      // ============================================================
      // LARGE STACK POINTER CHANGE (potential stack corruption)
      // ============================================================
      if (current_sp !== last_sp) begin
        // Check for suspicious SP changes
        if (last_sp != 0 && current_sp < 32'h00001000) begin
          $display("");
          $display("!!! WARNING: SP very low (0x%08h) at t=%0t !!!", current_sp, $time);
          $display("!!! Previous SP was 0x%08h", last_sp);
          $display("!!! PC = 0x%08h", current_pc);
          $display("");
        end
        last_sp <= current_sp;
      end
      
      last_pc <= current_pc;
      last_mstatus <= dut.u_cpu.csr_mstatus;
    end
  end

  // UART capture and display
  always @(posedge clk25) begin
    if (rst_n && dut.d_we && dut.d_addr == 32'hFFFF_FFF0) begin
      if (rx_count < 4096) begin
        rx_mem[rx_count] <= dut.d_wdata[7:0];
        rx_count <= rx_count + 1;
        if (dut.d_wdata[7:0] >= 32 && dut.d_wdata[7:0] < 127)
          $write("%c", dut.d_wdata[7:0]);
        else if (dut.d_wdata[7:0] == 10)
          $write("\n");
      end
    end
  end

  // Main test sequence
  integer wait_ms;
  initial begin
    $display("================================================");
    $display("  DEBUG TESTBENCH - Enhanced Trap Diagnostics");
    $display("================================================");
    $display("");
    
    rst_n = 0;
    #100;
    rst_n = 1;

    // Run for 100ms (configurable)
    wait_ms = 0;
    while (wait_ms < 100) begin
      #(1_000_000); // 1 ms
      wait_ms = wait_ms + 1;
      if (wait_ms % 20 == 0) begin
        $display("");
        $display("[SIM] %0d ms | PC=0x%08h SP=0x%08h | traps=%0d ecalls=%0d timers=%0d", 
                 wait_ms, current_pc, current_sp, trap_count, ecall_count, timer_int_count);
      end
    end

    $display("");
    $display("================================================");
    $display("  SIMULATION SUMMARY");
    $display("================================================");
    $display("  Duration:    %0d ms", wait_ms);
    $display("  UART bytes:  %0d", rx_count);
    $display("  Restarts:    %0d", restart_count);
    $display("  Total traps: %0d", trap_count);
    $display("  - Ecalls:    %0d", ecall_count);
    $display("  - Timer IRQ: %0d", timer_int_count);
    $display("================================================");
    
    $finish;
  end
endmodule

