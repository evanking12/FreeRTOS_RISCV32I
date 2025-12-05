`timescale 1ns/1ps

// Firmware simulation testbench
// Runs the actual compiled firmware and captures UART output
module firmware_sim_tb;

    reg clk = 0;
    reg rst_n = 0;
    
    // Clock: 100 MHz = 10ns period
    always #5 clk = ~clk;
    
    // UART TX capture
    wire uart_tx;
    reg [7:0] uart_rx_byte;
    reg uart_rx_valid;
    
    // Instantiate the full CPU top
    cpu_top uut (
        .clk100(clk),
        .rst_n(rst_n),
        .btn0(1'b0),
        .sw(2'b00),
        .led(),
        .uart_tx(uart_tx),
        .uart_rx(1'b1)  // Idle high
    );
    
    // Track PC for debugging
    wire [31:0] pc = uut.pc;
    wire [31:0] instr = uut.instr;
    
    // UART bit capture (115200 baud @ 100MHz = 868 cycles/bit)
    localparam BAUD_CYCLES = 868;
    reg [31:0] uart_bit_counter = 0;
    reg [3:0] uart_bit_idx = 0;
    reg [9:0] uart_shift_reg = 10'h3FF;
    reg uart_active = 0;
    reg uart_tx_prev = 1;
    
    // Capture UART output
    always @(posedge clk) begin
        uart_tx_prev <= uart_tx;
        uart_rx_valid <= 0;
        
        // Detect start bit (falling edge)
        if (!uart_active && uart_tx_prev && !uart_tx) begin
            uart_active <= 1;
            uart_bit_counter <= BAUD_CYCLES / 2;  // Sample in middle of bit
            uart_bit_idx <= 0;
        end
        
        if (uart_active) begin
            if (uart_bit_counter == 0) begin
                uart_shift_reg <= {uart_tx, uart_shift_reg[9:1]};
                uart_bit_idx <= uart_bit_idx + 1;
                uart_bit_counter <= BAUD_CYCLES;
                
                if (uart_bit_idx == 9) begin
                    uart_active <= 0;
                    uart_rx_byte <= uart_shift_reg[9:2];
                    uart_rx_valid <= 1;
                end
            end else begin
                uart_bit_counter <= uart_bit_counter - 1;
            end
        end
    end
    
    // Print UART characters
    always @(posedge clk) begin
        if (uart_rx_valid) begin
            if (uart_rx_byte >= 32 && uart_rx_byte < 127)
                $write("%c", uart_rx_byte);
            else if (uart_rx_byte == 10)
                $write("\n");
            else if (uart_rx_byte == 13)
                ; // Ignore CR
            else
                $write("[0x%02x]", uart_rx_byte);
        end
    end
    
    // PC watchdog - detect if PC gets stuck
    reg [31:0] last_pc = 0;
    reg [31:0] pc_stuck_counter = 0;
    
    always @(posedge clk) begin
        if (pc != last_pc) begin
            last_pc <= pc;
            pc_stuck_counter <= 0;
        end else begin
            pc_stuck_counter <= pc_stuck_counter + 1;
            if (pc_stuck_counter == 1000000) begin
                $display("\n[SIM] PC stuck at 0x%08x for 1M cycles - halting", pc);
                $finish;
            end
        end
    end
    
    // Monitor for restart detection
    reg [31:0] restart_count = 0;
    always @(posedge clk) begin
        if (pc == 32'h00000000 && last_pc != 32'h00000000 && last_pc != 32'hxxxxxxxx) begin
            restart_count <= restart_count + 1;
            $display("\n[SIM] !!! RESTART DETECTED !!! (count=%0d, came from PC=0x%08x)", restart_count, last_pc);
            if (restart_count >= 3) begin
                $display("[SIM] Too many restarts - stopping simulation");
                $finish;
            end
        end
    end
    
    // Simulation control
    initial begin
        $display("[SIM] Starting firmware simulation...");
        $display("[SIM] Monitoring PC and UART output");
        $display("[SIM] Will stop on: 3 restarts OR PC stuck for 1M cycles");
        $display("========================================");
        
        // Reset
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        
        // Run for a while (10 million cycles = 100ms at 100MHz)
        repeat(10_000_000) @(posedge clk);
        
        $display("\n========================================");
        $display("[SIM] Simulation complete (10M cycles)");
        $finish;
    end

endmodule

