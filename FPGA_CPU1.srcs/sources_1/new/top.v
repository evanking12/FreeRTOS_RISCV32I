`timescale 1ns / 1ps

// top.v - Top-level wrapper for Arty A7 board
module top (
    input  wire        clk100,
    input  wire        btn0,    // step button (unused)
    input  wire        btn1,    // reset button (active high here)
    input  wire [1:0]  sw,
    output wire [3:0]  led,
    output wire        uart_tx,
    input  wire        uart_rx
);

    // -----------------------------
    // Clock Divider: 100MHz -> 25MHz (divide by 4)
    // This gives plenty of timing margin
    // -----------------------------
    reg [1:0] clk_div = 0;
    always @(posedge clk100) begin
        clk_div <= clk_div + 1;
    end
    wire clk50 = clk_div[1];  // 25 MHz (using bit 1 = divide by 4)

    // -----------------------------
    // Reset handling (active-low)
    // Synchronize reset to 50MHz domain
    // -----------------------------
    reg [2:0] rst_sync = 3'b000;
    always @(posedge clk50) begin
        rst_sync <= {rst_sync[1:0], ~btn1};
    end
    wire rst_n = rst_sync[2];

    // -----------------------------
    // Instantiate CPU (runs at 50MHz now)
    // -----------------------------
    wire [3:0] led_out;

    cpu_top u_cpu_top (
        .clk100 (clk50),      // Actually 50MHz now!
        .rst_n  (rst_n),
        .btn0   (btn0),
        .sw     (sw),
        .led    (led_out),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx)
    );

    // -----------------------------
    // Drive LEDs
    // -----------------------------
    assign led = led_out;

endmodule
