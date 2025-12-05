`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  wire clk,
    input  wire rst,       // active high
    input  wire tx_start,
    input  wire [7:0] tx_data,
    output wire tx_busy,
    output reg  tx
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;
    reg [15:0] clk_count = 0;
    reg [3:0]  bit_index = 0;
    reg [9:0]  shift_reg = 10'b1111111111; // idle high
    reg busy = 0;
    assign tx_busy = busy;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx        <= 1'b1;
            busy      <= 1'b0;
            clk_count <= 0;
            bit_index <= 0;
            shift_reg <= 10'h3FF;
        end else begin
            if (tx_start && !busy) begin
                shift_reg <= {1'b1, tx_data, 1'b0};
                busy      <= 1'b1;
                clk_count <= 0;
                bit_index <= 0;
            end else if (busy) begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 0;
                    tx        <= shift_reg[bit_index];
                    bit_index <= bit_index + 1;
                    if (bit_index == 9)
                        busy <= 1'b0;
                end else begin
                    clk_count <= clk_count + 1;
                end
            end
        end
    end
endmodule
