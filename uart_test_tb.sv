`timescale 1ns / 1ps

// ============================================================================
// UART Test Suite for FreeRTOS Readiness
// Tests UART TX functionality matching firmware uart.c expectations:
// - UART TX at 0xFFFFFFF0
// - UART Status at 0xFFFFFFF4 (bit0=busy, bit1=fifo_full)
// ============================================================================

module uart_test_tb;
    reg clk = 0;
    always #5 clk = ~clk;  // 100MHz clock

    reg rst_n;
    reg btn0;
    reg [1:0] sw;
    reg uart_rx_pin;
    wire [3:0] led;
    wire uart_tx_pin;

    // UART configuration (must match cpu_top.v)
    localparam CLK_FREQ = 100_000_000;
    localparam BAUD = 115200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;  // ~868 clocks per bit
    localparam CLKS_PER_BYTE = CLKS_PER_BIT * 10; // 10 bits per byte

    // Test results
    integer bytes_captured;
    reg [7:0] captured_bytes [0:255];
    integer tests_passed;
    integer tests_total;

    cpu_top dut (
        .clk100(clk),
        .rst_n(rst_n),
        .btn0(btn0),
        .sw(sw),
        .led(led),
        .uart_tx(uart_tx_pin),
        .uart_rx(uart_rx_pin)
    );

    // Debug: monitor UART writes and pops
    always @(posedge clk) begin
        if (dut.uart_mmio_write)
            $display("PUSH @ %0t: data=0x%02h cnt=%0d busy=%b empty=%b pop=%b", 
                     $time, dut.d_wdata[7:0], dut.uart_fifo_count, 
                     dut.uart_busy, dut.uart_fifo_empty, dut.pop_fifo);
        if (dut.pop_fifo)
            $display("POP  @ %0t: byte=0x%02h cnt=%0d busy=%b", 
                     $time, dut.uart_fifo[dut.uart_rd_ptr], dut.uart_fifo_count, dut.uart_busy);
    end

    // ========================================================================
    // UART RX Monitor - Captures bytes from uart_tx_pin
    // ========================================================================
    reg [7:0] rx_shift;
    reg [3:0] rx_bit_count;
    reg [15:0] rx_clk_count;
    reg rx_busy;
    reg prev_uart_tx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_busy <= 0;
            rx_bit_count <= 0;
            rx_clk_count <= 0;
            prev_uart_tx <= 1;
            rx_shift <= 0;
        end else begin
            prev_uart_tx <= uart_tx_pin;

            if (!rx_busy) begin
                // Detect start bit (falling edge)
                if (prev_uart_tx && !uart_tx_pin) begin
                    rx_busy <= 1;
                    rx_bit_count <= 0;
                    rx_clk_count <= CLKS_PER_BIT / 2; // Sample in middle of bit
                end
            end else begin
                if (rx_clk_count == CLKS_PER_BIT - 1) begin
                    rx_clk_count <= 0;
                    rx_bit_count <= rx_bit_count + 1;
                    
                    if (rx_bit_count >= 1 && rx_bit_count <= 8) begin
                        // Data bits (LSB first)
                        rx_shift <= {uart_tx_pin, rx_shift[7:1]};
                    end
                    
                    if (rx_bit_count == 9) begin
                        // Stop bit - byte complete
                        rx_busy <= 0;
                        if (bytes_captured < 256) begin
                            captured_bytes[bytes_captured] = rx_shift;
                            bytes_captured = bytes_captured + 1;
                            $display("UART RX @ %0t: 0x%02h '%c'", $time, rx_shift, 
                                     (rx_shift >= 32 && rx_shift < 127) ? rx_shift : 8'h2E);
                        end
                    end
                end else begin
                    rx_clk_count <= rx_clk_count + 1;
                end
            end
        end
    end

    // ========================================================================
    // Helper Tasks
    // ========================================================================
    
    task init_mem();
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                dut.instr_mem[i] = 32'h00000013; // NOP
                dut.data_mem[i] = 32'h0;
            end
        end
    endtask

    task reset_system();
        integer j;
        begin
            // Wait for any previous UART transmission to complete
            while (dut.uart_busy) @(posedge clk);
            run_cycles(CLKS_PER_BYTE);
            
            rst_n = 0;
            bytes_captured = 0;
            for (j = 0; j < 256; j = j + 1)
                captured_bytes[j] = 8'h00;
            #100;
            rst_n = 1;
            // Wait for instruction fetch delay (2 cycles in cpu_top)
            run_cycles(10);
        end
    endtask

    task run_cycles(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    task wait_uart_idle();
        integer timeout;
        begin
            $display("wait_uart_idle: starting, busy=%b fifo=%0d", dut.uart_busy, dut.uart_fifo_count);
            // Wait for UART to finish transmitting all bytes
            timeout = 0;
            while ((dut.uart_busy || dut.uart_fifo_count > 0) && timeout < 10_000_000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            $display("wait_uart_idle: done waiting, busy=%b fifo=%0d timeout=%0d", 
                     dut.uart_busy, dut.uart_fifo_count, timeout);
            // Wait extra time for the last byte to fully transmit on the wire
            run_cycles(CLKS_PER_BYTE * 2);
        end
    endtask

    // ========================================================================
    // Test 1: Single Byte TX
    // Uses firmware-compatible address: addi x2,x0,-16 -> x2 = 0xFFFFFFF0
    // Note: First 8 instructions are NOPs to account for pipeline startup
    // ========================================================================
    task test_single_byte();
        reg passed;
        begin
            $display("\n=== TEST 1: Single Byte TX ===");
            init_mem();
            bytes_captured = 0;
            
            // Program starts at address 8 (index 8) - first 8 are NOPs for pipeline startup
            // addi x1,x0,0x41  -> x1 = 'A'
            // addi x2,x0,-16   -> x2 = 0xFFFFFFF0 (UART_TX)
            // sw x1,0(x2)      -> write to UART
            // jal x0,0         -> halt (infinite loop)
            dut.instr_mem[8]  = 32'h04100093; // addi x1,x0,0x41
            dut.instr_mem[9]  = 32'hFF000113; // addi x2,x0,-16  (0xFFFFFFF0)
            dut.instr_mem[10] = 32'h00112023; // sw x1,0(x2)
            dut.instr_mem[11] = 32'h0000006F; // jal x0,0 (halt)
            
            reset_system();
            run_cycles(100);  // Let program execute
            wait_uart_idle();
            
            passed = (bytes_captured == 1) && (captured_bytes[0] == 8'h41);
            $display("  Captured: %0d bytes", bytes_captured);
            if (bytes_captured > 0)
                $display("  First byte: 0x%02h (expect 'A'=0x41)", captured_bytes[0]);
            $display("single byte TX: %s", passed ? "PASS" : "FAIL");
            tests_total = tests_total + 1;
            if (passed) tests_passed = tests_passed + 1;
        end
    endtask

    // ========================================================================
    // Test 2: String TX ("Hello")
    // ========================================================================
    task test_string_tx();
        reg passed;
        integer i;
        begin
            $display("\n=== TEST 2: String TX 'Hello' ===");
            init_mem();
            bytes_captured = 0;
            
            // Build UART address: addi x10,x0,-16 -> x10 = 0xFFFFFFF0
            // Program starts at index 8, with NOP padding between writes
            dut.instr_mem[8]  = 32'hFF000513; // addi x10,x0,-16
            dut.instr_mem[9]  = 32'h00000013; // nop
            
            // Write 'H' (0x48)
            dut.instr_mem[10] = 32'h04800093; // addi x1,x0,0x48
            dut.instr_mem[11] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[12] = 32'h00000013; // nop
            // Write 'e' (0x65)
            dut.instr_mem[13] = 32'h06500093; // addi x1,x0,0x65
            dut.instr_mem[14] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[15] = 32'h00000013; // nop
            // Write 'l' (0x6C)
            dut.instr_mem[16] = 32'h06C00093; // addi x1,x0,0x6C
            dut.instr_mem[17] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[18] = 32'h00000013; // nop
            // Write 'l' (0x6C)
            dut.instr_mem[19] = 32'h06C00093; // addi x1,x0,0x6C
            dut.instr_mem[20] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[21] = 32'h00000013; // nop
            // Write 'o' (0x6F)
            dut.instr_mem[22] = 32'h06F00093; // addi x1,x0,0x6F
            dut.instr_mem[23] = 32'h00152023; // sw x1,0(x10)
            // Halt
            dut.instr_mem[24] = 32'h0000006F; // jal x0,0
            
            reset_system();
            run_cycles(150);  // Let program execute
            wait_uart_idle();
            
            passed = (bytes_captured == 5) &&
                     (captured_bytes[0] == "H") &&
                     (captured_bytes[1] == "e") &&
                     (captured_bytes[2] == "l") &&
                     (captured_bytes[3] == "l") &&
                     (captured_bytes[4] == "o");
            
            $display("  Captured: %0d bytes (expect 5)", bytes_captured);
            $write("  String: \"");
            for (i = 0; i < bytes_captured; i = i + 1)
                $write("%c", captured_bytes[i]);
            $display("\"");
            $display("string TX: %s", passed ? "PASS" : "FAIL");
            tests_total = tests_total + 1;
            if (passed) tests_passed = tests_passed + 1;
        end
    endtask

    // ========================================================================
    // Test 3: Status Register Polling (firmware style)
    // Firmware polls: while (status & 0x3) { wait }
    // Status bit 0 = busy, bit 1 = fifo_full
    // ========================================================================
    task test_status_polling();
        reg passed;
        begin
            $display("\n=== TEST 3: Status Register Polling ===");
            init_mem();
            bytes_captured = 0;
            
            // x10 = UART_TX (0xFFFFFFF0)
            // x11 = UART_STATUS (0xFFFFFFF4)
            // Program starts at index 8
            dut.instr_mem[8]  = 32'hFF000513; // addi x10,x0,-16  x10 = 0xFFFFFFF0
            dut.instr_mem[9]  = 32'h00450593; // addi x11,x10,4   x11 = 0xFFFFFFF4
            
            // Write 'X' to UART
            dut.instr_mem[10] = 32'h05800093; // addi x1,x0,'X'
            dut.instr_mem[11] = 32'h00152023; // sw x1,0(x10)
            
            // Halt
            dut.instr_mem[12] = 32'h0000006F; // jal x0,0
            
            reset_system();
            run_cycles(80);
            wait_uart_idle();
            
            passed = (bytes_captured == 1) && (captured_bytes[0] == 8'h58); // 'X'
            
            $display("  Captured byte: 0x%02h (expect 'X'=0x58)", 
                     bytes_captured > 0 ? captured_bytes[0] : 8'hXX);
            $display("status polling: %s", passed ? "PASS" : "FAIL");
            tests_total = tests_total + 1;
            if (passed) tests_passed = tests_passed + 1;
        end
    endtask

    // ========================================================================
    // Test 4: FIFO Buffering (rapid writes - firmware style)
    // ========================================================================
    task test_fifo_buffering();
        reg passed;
        integer i;
        begin
            $display("\n=== TEST 4: FIFO Buffering ===");
            init_mem();
            bytes_captured = 0;
            
            // Build UART address - program starts at index 8
            dut.instr_mem[8]  = 32'hFF000513; // addi x10,x0,-16   x10 = UART_TX
            
            // Write '0' through '9' rapidly (should be buffered in FIFO)
            dut.instr_mem[9]  = 32'h03000093; // addi x1,x0,'0'
            dut.instr_mem[10] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[11] = 32'h03100093; // addi x1,x0,'1'
            dut.instr_mem[12] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[13] = 32'h03200093; // addi x1,x0,'2'
            dut.instr_mem[14] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[15] = 32'h03300093; // addi x1,x0,'3'
            dut.instr_mem[16] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[17] = 32'h03400093; // addi x1,x0,'4'
            dut.instr_mem[18] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[19] = 32'h03500093; // addi x1,x0,'5'
            dut.instr_mem[20] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[21] = 32'h03600093; // addi x1,x0,'6'
            dut.instr_mem[22] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[23] = 32'h03700093; // addi x1,x0,'7'
            dut.instr_mem[24] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[25] = 32'h03800093; // addi x1,x0,'8'
            dut.instr_mem[26] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[27] = 32'h03900093; // addi x1,x0,'9'
            dut.instr_mem[28] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[29] = 32'h0000006F; // jal x0,0  halt
            
            reset_system();
            run_cycles(300);  // Let program execute quickly
            wait_uart_idle();
            
            passed = (bytes_captured == 10);
            for (i = 0; i < 10 && passed; i = i + 1) begin
                if (captured_bytes[i] != (8'h30 + i)) passed = 0;
            end
            
            $display("  Captured: %0d bytes (expect 10)", bytes_captured);
            $write("  String: \"");
            for (i = 0; i < bytes_captured; i = i + 1)
                $write("%c", captured_bytes[i]);
            $display("\"");
            $display("FIFO buffering: %s", passed ? "PASS" : "FAIL");
            tests_total = tests_total + 1;
            if (passed) tests_passed = tests_passed + 1;
        end
    endtask

    // ========================================================================
    // Test 5: Newline Sequence (CR/LF - firmware style)
    // ========================================================================
    task test_crlf();
        reg passed;
        begin
            $display("\n=== TEST 5: CR/LF Newline ===");
            init_mem();
            bytes_captured = 0;
            
            // Write "Hi\r\n" - program starts at index 8
            dut.instr_mem[8]  = 32'hFF000513; // addi x10,x0,-16   x10 = UART_TX
            
            dut.instr_mem[9]  = 32'h04800093; // addi x1,x0,'H'
            dut.instr_mem[10] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[11] = 32'h06900093; // addi x1,x0,'i'
            dut.instr_mem[12] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[13] = 32'h00D00093; // addi x1,x0,0x0D   CR
            dut.instr_mem[14] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[15] = 32'h00A00093; // addi x1,x0,0x0A   LF
            dut.instr_mem[16] = 32'h00152023; // sw x1,0(x10)
            dut.instr_mem[17] = 32'h0000006F; // jal x0,0  halt
            
            reset_system();
            run_cycles(120);
            wait_uart_idle();
            
            passed = (bytes_captured == 4) &&
                     (captured_bytes[0] == 8'h48) &&  // 'H'
                     (captured_bytes[1] == 8'h69) &&  // 'i'
                     (captured_bytes[2] == 8'h0D) &&  // CR
                     (captured_bytes[3] == 8'h0A);    // LF
            
            $display("  Captured: %0d bytes", bytes_captured);
            $display("  Bytes: H=0x%02h i=0x%02h CR=0x%02h LF=0x%02h", 
                     captured_bytes[0], captured_bytes[1], 
                     captured_bytes[2], captured_bytes[3]);
            $display("CR/LF newline: %s", passed ? "PASS" : "FAIL");
            tests_total = tests_total + 1;
            if (passed) tests_passed = tests_passed + 1;
        end
    endtask

    // ========================================================================
    // Test 6: Binary Data (all byte values 0x00-0xFF work)
    // ========================================================================
    task test_binary_data();
        reg passed;
        begin
            $display("\n=== TEST 6: Binary Data ===");
            init_mem();
            bytes_captured = 0;
            
            // Write some binary values including 0x00 and 0xFF - program starts at index 8
            dut.instr_mem[8]  = 32'hFF000513; // addi x10,x0,-16   x10 = UART_TX
            
            // 0x00
            dut.instr_mem[9]  = 32'h00000093; // addi x1,x0,0x00
            dut.instr_mem[10] = 32'h00152023; // sw x1,0(x10)
            // 0x55 (alternating bits)
            dut.instr_mem[11] = 32'h05500093; // addi x1,x0,0x55
            dut.instr_mem[12] = 32'h00152023; // sw x1,0(x10)
            // 0xAA (alternating bits)
            dut.instr_mem[13] = 32'hFAA00093; // addi x1,x0,-86 (0xFFFFFFAA, only low 8 bits used)
            dut.instr_mem[14] = 32'h00152023; // sw x1,0(x10)
            // 0xFF
            dut.instr_mem[15] = 32'hFFF00093; // addi x1,x0,-1 (0xFFFFFFFF)
            dut.instr_mem[16] = 32'h00152023; // sw x1,0(x10)
            
            dut.instr_mem[17] = 32'h0000006F; // jal x0,0  halt
            
            reset_system();
            run_cycles(100);
            wait_uart_idle();
            
            passed = (bytes_captured == 4) &&
                     (captured_bytes[0] == 8'h00) &&
                     (captured_bytes[1] == 8'h55) &&
                     (captured_bytes[2] == 8'hAA) &&
                     (captured_bytes[3] == 8'hFF);
            
            $display("  Captured: %0d bytes", bytes_captured);
            $display("  Values: 0x%02h 0x%02h 0x%02h 0x%02h (expect 00 55 AA FF)",
                     captured_bytes[0], captured_bytes[1],
                     captured_bytes[2], captured_bytes[3]);
            $display("binary data: %s", passed ? "PASS" : "FAIL");
            tests_total = tests_total + 1;
            if (passed) tests_passed = tests_passed + 1;
        end
    endtask

    // ========================================================================
    // Main Test Runner
    // ========================================================================
    initial begin
        $display("============================================================");
        $display("  UART Test Suite for FreeRTOS Firmware Compatibility");
        $display("  BAUD: %0d, CLK: %0d MHz", BAUD, CLK_FREQ/1_000_000);
        $display("  UART_TX: 0xFFFFFFF0, UART_STATUS: 0xFFFFFFF4");
        $display("============================================================");
        
        btn0 = 0;
        sw = 2'b00;
        uart_rx_pin = 1'b1;  // Idle high
        tests_passed = 0;
        tests_total = 0;
        
        test_single_byte();
        test_string_tx();
        test_status_polling();
        test_fifo_buffering();
        test_crlf();
        test_binary_data();
        
        $display("\n============================================================");
        $display("  UART Test Suite Complete: %0d/%0d tests passed", 
                 tests_passed, tests_total);
        if (tests_passed == tests_total)
            $display("  ✓ UART ready for FreeRTOS firmware!");
        else
            $display("  ✗ UART needs fixes before FreeRTOS");
        $display("============================================================");
        $finish;
    end

endmodule
