`timescale 1ns / 1ps

module cpu_top (
    input  wire        clk100,
    input  wire        rst_n,      // active-low reset (map to BTN1 if desired)
    input  wire        btn0,       // unused (kept for compatibility)
    input  wire [1:0]  sw,         // unused (kept for compatibility)
    output wire [3:0]  led,
    output wire        uart_tx,
    input  wire        uart_rx
);
    // ROM (128 KB, 32768 words)
    reg [31:0] instr_mem[0:32767];

    // Data RAM (128 KB, 32768 words)
    localparam integer DATA_WORDS = 32768;
    reg [31:0] data_mem[0:DATA_WORDS-1];

    integer i;
    initial begin
        // Initialize ALL memory to 0 first (prevents X in simulation)
        for (i = 0; i < 32768; i = i + 1) begin
            instr_mem[i] = 32'h00000013;  // NOP instruction
            data_mem[i] = 32'h0;
        end
        
        // Initialize UART FIFO to 0
        for (i = 0; i < UART_FIFO_DEPTH; i = i + 1) begin
            uart_fifo[i] = 8'h0;
        end
        
        // Try to load firmware from multiple possible paths
        $readmemh("instr_mem.vh", instr_mem);
        
        // Copy code to data memory (unified memory model)
        for (i = 0; i < DATA_WORDS; i = i + 1)
            data_mem[i] = instr_mem[i];
            
        $display("[cpu_top] Memory initialized. instr_mem[0]=0x%08h", instr_mem[0]);
    end

    reg  [1:0]  instr_fetch_delay;

    always @(posedge clk100 or negedge rst_n) begin
        if (!rst_n)
            instr_fetch_delay <= 2'd0;
        else if (instr_fetch_delay != 2'd2)
            instr_fetch_delay <= instr_fetch_delay + 1;
    end

    // CPU core wires
    wire [31:0] pc;
    wire        instr_ready = (instr_fetch_delay == 2'd2);
    wire [13:0] instr_idx = instr_ready ? pc[15:2] : 14'd0;
    wire [31:0] instr = instr_mem[instr_idx];
    wire [31:0] d_addr, d_wdata;
    wire [31:0] d_rdata;
    wire        d_we;
    wire        is_sw, is_sh, is_sb;
    wire [31:0] rs2_val;
    wire [31:0] wb_value;

    localparam [31:0] UART_TX_ADDR     = 32'hFFFF_FFF0;
    localparam [31:0] UART_STATUS_ADDR = 32'hFFFF_FFF4;
    localparam [31:0] UART_RX_ADDR     = 32'hFFFF_FFF8;
    localparam [31:0] RAM_BASE         = 32'h0000_0000;
    localparam [31:0] RAM_END          = (DATA_WORDS * 4) - 1;
    localparam [31:0] CLINT_BASE       = 32'hFFFF_0000;
    localparam [31:0] CLINT_END        = 32'hFFFF_001F;
    localparam [31:0] CSR_MTVEC_ADDR   = 32'hFFFF_FFC0;
    localparam [31:0] CSR_MSTATUS_ADDR = 32'hFFFF_FFC4;
    localparam [31:0] CSR_MEPC_ADDR    = 32'hFFFF_FFC8;
    localparam [31:0] CSR_MCAUSE_ADDR  = 32'hFFFF_FFCC;
    localparam integer UART_FIFO_DEPTH = 256;

    (* dont_touch = "true" *) reg [7:0] uart_fifo [0:UART_FIFO_DEPTH-1];
    (* dont_touch = "true" *) reg [7:0] uart_wr_ptr;
    (* dont_touch = "true" *) reg [7:0] uart_rd_ptr;
    (* dont_touch = "true" *) reg [8:0] uart_fifo_count;
    (* dont_touch = "true" *) reg [7:0] uart_byte;

    // Data RAM read
    wire [13:0] data_idx = d_addr[15:2];
    wire is_uart_tx      = (d_addr == UART_TX_ADDR);
    wire is_uart_status  = (d_addr == UART_STATUS_ADDR);
    wire mem_sel = ~(is_uart_tx | is_uart_status);
    wire ram_access = (d_addr >= RAM_BASE) && (d_addr <= RAM_END);
    wire clint_access = (d_addr >= CLINT_BASE) && (d_addr <= CLINT_END);
    wire csr_mmio_access =
        (d_addr == CSR_MTVEC_ADDR) ||
        (d_addr == CSR_MSTATUS_ADDR) ||
        (d_addr == CSR_MEPC_ADDR) ||
        (d_addr == CSR_MCAUSE_ADDR);
    wire uart_fifo_empty = (uart_fifo_count == 0);
    wire uart_fifo_full  = (uart_fifo_count == UART_FIFO_DEPTH);
    
    // UART RX handling - latch received data until CPU reads it
    reg [7:0] rx_data_reg;
    reg       rx_data_valid;
    wire is_uart_rx = (d_addr == UART_RX_ADDR);
    wire uart_rx_read = is_uart_rx && !d_we;  // CPU reading RX register
    
    always @(posedge clk100 or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_reg <= 8'd0;
            rx_data_valid <= 1'b0;
        end else begin
            if (rx_valid) begin
                // New byte received from UART
                rx_data_reg <= rx_data;
                rx_data_valid <= 1'b1;
            end else if (uart_rx_read) begin
                // CPU read the byte, clear valid flag
                rx_data_valid <= 1'b0;
            end
        end
    end
    
    // Status register: bit 0 = TX busy, bit 1 = TX FIFO full, bit 2 = RX valid
    wire [31:0] uart_status = {29'b0, rx_data_valid, uart_fifo_full, uart_busy};
    
    assign d_rdata =
        is_uart_status    ? uart_status :
        is_uart_rx        ? {24'b0, rx_data_reg} :
        ram_access        ? data_mem[data_idx] :
        clint_access      ? 32'h0 :
        csr_mmio_access   ? 32'h0 :
        32'h0;

    // UART TX handling with FIFO buffering
    wire uart_busy;
    reg  uart_start;
    // CRITICAL: Stall CPU until instr_fetch_delay is complete!
    // Without this, PC increments while instr_idx is forced to 0,
    // causing auipc to see wrong id_pc value (4 instead of 0)
    wire step_pulse = instr_ready;
    wire write_enable    = d_we;
    wire write_mem       = write_enable && mem_sel && ram_access;
    wire uart_mmio_write = d_we && is_uart_tx;
    wire push_fifo       = uart_mmio_write && !uart_fifo_full;
    
    // Pop only when idle and FIFO has data, but NOT while uart_start is still high
    // This prevents double-popping during the 1-cycle gap before uart_tx sees uart_start
    wire pop_fifo        = (!uart_busy) && !uart_fifo_empty && !uart_start;

    // Data RAM writes
    reg [31:0] w;
    always @(posedge clk100) begin
        if (write_mem) begin
            w = data_mem[data_idx];
            if (is_sw) begin
                w = d_wdata;
            end else if (is_sh) begin
                case (d_addr[1])
                    1'b0: w[15:0]  = d_wdata[15:0];
                    1'b1: w[31:16] = d_wdata[15:0];
                endcase
            end else if (is_sb) begin
                case (d_addr[1:0])
                    2'b00: w[7:0]   = d_wdata[7:0];
                    2'b01: w[15:8]  = d_wdata[7:0];
                    2'b10: w[23:16] = d_wdata[7:0];
                    2'b11: w[31:24] = d_wdata[7:0];
                endcase
            end
            data_mem[data_idx] <= w;
        end
    end

    always @(posedge clk100 or negedge rst_n) begin
        if (!rst_n) begin
            uart_start      <= 1'b0;
            uart_wr_ptr     <= 8'd0;
            uart_rd_ptr     <= 8'd0;
            uart_fifo_count <= 9'd0;
            uart_byte       <= 8'h00;
        end else begin
            uart_start <= 1'b0;

            if (push_fifo) begin
                uart_fifo[uart_wr_ptr] <= d_wdata[7:0];
                uart_wr_ptr <= uart_wr_ptr + 1'b1;
            end

            if (pop_fifo) begin
                uart_byte <= uart_fifo[uart_rd_ptr];
                uart_rd_ptr <= uart_rd_ptr + 1'b1;
                uart_start <= 1'b1;
            end

            case ({push_fifo, pop_fifo})
                2'b10: uart_fifo_count <= uart_fifo_count + 1'b1;
                2'b01: uart_fifo_count <= uart_fifo_count - 1'b1;
                default: uart_fifo_count <= uart_fifo_count;
            endcase
        end
    end

    // CPU core
    cpu_core u_cpu (
        .clk(clk100),
        .rst_n(rst_n),
        .step_pulse(step_pulse),
        .irq_i(1'b0),
        .pc_o(pc),
        .instr_i(instr),
        .d_addr(d_addr),
        .d_wdata(d_wdata),
        .d_rdata(d_rdata),
        .d_we(d_we),
        .wb_value(wb_value),
        .is_sw_o(is_sw),
        .is_sh_o(is_sh),
        .is_sb_o(is_sb),
        .rs2_val_o(rs2_val)
    );

    // UART RX (available for future use)
    wire [7:0] rx_data;
    wire       rx_valid;
    uart_rx #(
        .CLK_HZ(25_000_000),     // 25 MHz after clock divider (100/4)
        .BIT_RATE(115200),
        .PAYLOAD_BITS(8)
    ) U_RX (
        .clk(clk100),
        .resetn(rst_n),
        .uart_rxd(uart_rx),
        .uart_rx_en(1'b1),
        .uart_rx_break(),
        .uart_rx_valid(rx_valid),
        .uart_rx_data(rx_data)
    );

    // UART TX direct to the pin (no extra register)
    uart_tx #(
        .CLK_FREQ(25_000_000),   // 25 MHz after clock divider (100/4)
        .BAUD(115200)
    ) U_TX (
        .clk(clk100),
        .rst(~rst_n),
        .tx_start(uart_start),
        .tx_data(uart_byte),
        .tx(uart_tx),
        .tx_busy(uart_busy)
    );

    // Heartbeat to confirm the core is running
    reg [25:0] heartbeat_ctr;
    always @(posedge clk100 or negedge rst_n) begin
        if (!rst_n)
            heartbeat_ctr <= 26'd0;
        else
            heartbeat_ctr <= heartbeat_ctr + 1'b1;
    end

    // LED debug
    assign led[0] = heartbeat_ctr[25];                 // heartbeat blinker
    assign led[1] = uart_busy;                        // pulse when UART write occurs
    assign led[2] = (pc[15:0] != 16'h0000);            // PC running
    assign led[3] = 1'b0;
endmodule
