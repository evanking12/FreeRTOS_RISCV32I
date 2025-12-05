`timescale 1ns / 1ps

module uart_rx #(
    parameter BIT_RATE     = 115200,
    parameter PAYLOAD_BITS = 8,
    parameter CLK_HZ       = 100_000_000,
    parameter STOP_BITS    = 1
)(
    input  wire clk,
    input  wire resetn,        // active low
    input  wire uart_rxd,
    input  wire uart_rx_en,
    output wire uart_rx_break,
    output reg  uart_rx_valid,
    output reg  [PAYLOAD_BITS-1:0] uart_rx_data
);
    localparam integer BIT_P        = 1_000_000_000 / BIT_RATE;      // ns
    localparam integer CLK_P        = 1_000_000_000 / CLK_HZ;        // ns
    localparam integer CYCLES_PER_BIT = BIT_P / CLK_P;
    localparam integer COUNT_REG_LEN  = 1 + $clog2(CYCLES_PER_BIT);

    reg [COUNT_REG_LEN-1:0] cycle_counter;
    reg [3:0] bit_counter;
    reg [PAYLOAD_BITS-1:0] rx_shift;
    reg [2:0] fsm_state, n_fsm_state;
    reg rxd_sync0, rxd_sync1;

    localparam FSM_IDLE  = 0;
    localparam FSM_START = 1;
    localparam FSM_RECV  = 2;
    localparam FSM_STOP  = 3;

    assign uart_rx_break = 1'b0; // not implemented here

    // sync RXD
    always @(posedge clk) begin
        rxd_sync0 <= uart_rxd;
        rxd_sync1 <= rxd_sync0;
    end

    wire next_bit    = cycle_counter == CYCLES_PER_BIT;
    wire payload_done= bit_counter   == PAYLOAD_BITS;
    wire stop_done   = bit_counter   == STOP_BITS && fsm_state == FSM_STOP;

    // next state
    always @(*) begin
        case (fsm_state)
            FSM_IDLE : n_fsm_state = (uart_rx_en && !rxd_sync1) ? FSM_START : FSM_IDLE;
            FSM_START: n_fsm_state = next_bit     ? FSM_RECV : FSM_START;
            FSM_RECV : n_fsm_state = payload_done ? FSM_STOP : FSM_RECV;
            FSM_STOP : n_fsm_state = stop_done    ? FSM_IDLE : FSM_STOP;
            default  : n_fsm_state = FSM_IDLE;
        endcase
    end

    // counters and shift
    always @(posedge clk) begin
        if (!resetn) begin
            cycle_counter <= 0;
            bit_counter   <= 0;
            rx_shift      <= 0;
            uart_rx_valid <= 1'b0;
            uart_rx_data  <= 0;
            fsm_state     <= FSM_IDLE;
        end else begin
            fsm_state <= n_fsm_state;
            uart_rx_valid <= 1'b0;

            case (fsm_state)
                FSM_IDLE: begin
                    cycle_counter <= 0;
                    bit_counter   <= 0;
                end
                FSM_START: begin
                    cycle_counter <= next_bit ? 0 : cycle_counter + 1;
                end
                FSM_RECV: begin
                    if (next_bit) begin
                        cycle_counter <= 0;
                        rx_shift <= {rxd_sync1, rx_shift[PAYLOAD_BITS-1:1]};
                        bit_counter <= bit_counter + 1;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end
                FSM_STOP: begin
                    if (next_bit) begin
                        cycle_counter <= 0;
                        bit_counter   <= bit_counter + 1;
                        if (stop_done) begin
                            uart_rx_valid <= 1'b1;
                            uart_rx_data  <= rx_shift;
                        end
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end
            endcase
        end
    end
endmodule
