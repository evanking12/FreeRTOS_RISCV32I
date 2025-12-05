`timescale 1ns/1ps

module tb_cpu;
  reg clk100_raw = 0;
  reg rst_n = 0;
  reg btn0 = 0;
  reg [1:0] sw = 2'b00;
  wire [3:0] led;
  wire uart_tx;
  reg uart_rx = 1'b1;

  // Clock divider: 100MHz -> 25MHz (same as top.v)
  reg [1:0] clk_div = 0;
  always @(posedge clk100_raw) clk_div <= clk_div + 1;
  wire clk25 = clk_div[1];  // 25 MHz

  cpu_top dut (
    .clk100(clk25),         // Pass 25MHz like real hardware!
    .rst_n(rst_n),
    .btn0(btn0),
    .sw(sw),
    .led(led),
    .uart_tx(uart_tx),
    .uart_rx(uart_rx)
  );

  always #5 clk100_raw = ~clk100_raw; // 100 MHz base clock

  reg [7:0] rx_mem [0:4095];
  integer rx_count = 0;
  integer wait_ms;
  integer i;

  // PC tracking for restart detection
  reg [31:0] last_pc = 0;
  wire [31:0] current_pc = dut.pc;
  integer restart_count = 0;
  
  // Detect restarts (PC jumps to 0 from somewhere else)
  // Also detect trap entry (PC jumps to mtvec = 0x12A0)
  reg trap_detected = 0;
  reg [31:0] last_mepc = 0;
  integer interrupt_count = 0;
  always @(posedge clk25) begin
    if (rst_n) begin
      // Detect restart
      if (current_pc == 32'h00000000 && last_pc != 32'h00000000 && last_pc !== 32'hxxxxxxxx) begin
        restart_count = restart_count + 1;
        $display("");
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("!!! RESTART #%0d DETECTED at time %0t", restart_count, $time);
        $display("!!! PC jumped to 0x00000000 from 0x%08h", last_pc);
        $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        $display("");
        
        if (restart_count >= 3) begin
          $display("Too many restarts - stopping simulation");
          $finish;
        end
      end
      
      // Detect REAL trap entry: PC jumps to mtvec (not just any mepc change!)
      // The old detection fired on csrw mepc from trap handler, causing false positives
      if (current_pc == dut.u_cpu.csr_mtvec && last_pc != dut.u_cpu.csr_mtvec && dut.u_cpu.csr_mtvec != 0) begin
        // Check if it's an interrupt (bit 31 set) or exception
        if (dut.u_cpu.csr_mcause[31]) begin
          // Interrupt - only print first few to avoid spam
          if (interrupt_count < 5) begin
            $display("[INT] Timer interrupt #%0d at time %0t, mepc=0x%08h", 
                     interrupt_count, $time, dut.u_cpu.csr_mepc);
          end
          interrupt_count <= interrupt_count + 1;
        end else begin
          // Exception - always print
          $display("");
          $display("!!! EXCEPTION at time %0t !!!", $time);
          $display("!!! mepc   = 0x%08h", dut.u_cpu.csr_mepc);
          $display("!!! mcause = 0x%08h", dut.u_cpu.csr_mcause);
          case (dut.u_cpu.csr_mcause)
            32'h0: $display("!!!   Cause: Instruction address misaligned");
            32'h2: $display("!!!   Cause: Illegal instruction");
            32'h4: $display("!!!   Cause: Load address misaligned");
            32'h6: $display("!!!   Cause: Store address misaligned");
            32'hB: $display("!!!   Cause: Environment call (ecall)");
            default: $display("!!!   Cause: Unknown");
          endcase
          $display("");
        end
        last_mepc <= dut.u_cpu.csr_mepc;
      end
      
      // DEBUG: Detect mret instruction (opcode 0x30200073)
      if (dut.u_cpu.id_inst == 32'h30200073) begin
        $display("[MRET] Detected at PC=0x%08h", current_pc);
        $display("  csr_mepc=0x%08h mstatus=0x%08h", dut.u_cpu.csr_mepc, dut.u_cpu.csr_mstatus);
        $display("  mret_flush=%b trap_flush=%b branch_flush=%b", 
                 dut.u_cpu.mret_flush, dut.u_cpu.trap_flush, dut.u_cpu.branch_flush);
        $display("  irq_take=%b timer_irq=%b mstatus_mie=%b system_op=%b",
                 dut.u_cpu.irq_take, dut.u_cpu.timer_irq_level, 
                 dut.u_cpu.csr_mstatus_mie, dut.u_cpu.system_op_in_pipeline);
        $display("  branch_flag=%b branch_target=0x%08h",
                 dut.u_cpu.branch_flag, dut.u_cpu.branch_target);
      end
      
      // DEBUG: Track PC for 5 cycles after mret
      if (last_pc == 32'h000052dc || last_pc == 32'h0000016c) begin
        $display("[POST-MRET] PC=0x%08h mstatus=0x%08h irq_take=%b trap_flush=%b",
                 current_pc, dut.u_cpu.csr_mstatus, dut.u_cpu.irq_take, dut.u_cpu.trap_flush);
      end
      
      // DEBUG: Detect csrw to mepc (opcode pattern for csrw mepc, rs)
      if (dut.u_cpu.id_inst[6:0] == 7'b1110011 && 
          dut.u_cpu.id_inst[14:12] == 3'b001 &&
          dut.u_cpu.id_inst[31:20] == 12'h341) begin
        $display("[CSRW MEPC] At PC=0x%08h, writing value (will appear next cycle)", current_pc);
      end
      
      last_pc <= current_pc;
    end
  end

  // Capture MMIO writes to UART TX and print characters
  always @(posedge clk25) begin
    if (rst_n && dut.d_we && dut.d_addr == 32'hFFFF_FFF0) begin
      if (rx_count < 4096) begin
        rx_mem[rx_count] <= dut.d_wdata[7:0];
        rx_count <= rx_count + 1;
        // Print character immediately
        if (dut.d_wdata[7:0] >= 32 && dut.d_wdata[7:0] < 127)
          $write("%c", dut.d_wdata[7:0]);
        else if (dut.d_wdata[7:0] == 10)
          $write("\n");
        else if (dut.d_wdata[7:0] == 13)
          ; // ignore CR
      end
    end
  end

  initial begin
    $display("================================================");
    $display("  FreeRTOS Firmware Simulation (25MHz clock)");
    $display("  UART output will appear below:");
    $display("================================================");
    $display("");
    
    rst_n = 0;
    #100;
    rst_n = 1;

    // Run simulation (500ms should be enough to see output)
    wait_ms = 0;
    while (wait_ms < 1000) begin
      #(1_000_000); // 1 ms of sim time
      wait_ms = wait_ms + 1;
      if (wait_ms % 100 == 0)
        $display("\n[SIM] %0d ms elapsed, PC=0x%08h, UART bytes=%0d", wait_ms, current_pc, rx_count);
    end

    $display("");
    $display("================================================");
    $display("Simulation complete!");
    $display("  UART bytes: %0d", rx_count);
    $display("  Restarts:   %0d", restart_count);
    $display("  Timer IRQs: %0d", interrupt_count);
    $display("================================================");
    
    $finish;
  end
endmodule
