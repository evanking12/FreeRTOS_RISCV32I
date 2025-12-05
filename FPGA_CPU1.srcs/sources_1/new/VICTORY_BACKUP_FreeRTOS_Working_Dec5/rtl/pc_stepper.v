`timescale 1ns / 1ps

module pc_stepper (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        step_btn,
    input  wire [1:0]  step_sel,
    output reg  [31:0] pc
);
    //-----------------------------------------------------------
    // Decode step size from switches
    //-----------------------------------------------------------
    wire [31:0] step_val =
        (step_sel == 2'b00) ? 32'd4  :
        (step_sel == 2'b01) ? 32'd8  :
        (step_sel == 2'b10) ? 32'd16 :
                              32'd32;

    //-----------------------------------------------------------
    // Rising-edge detection for step button
    //-----------------------------------------------------------
    reg step_btn_d;
    wire step_pulse = step_btn & ~step_btn_d;

    always @(posedge clk) begin
        step_btn_d <= step_btn;

        if (!rst_n)
            pc <= 32'd0;
        else if (step_pulse)
            pc <= pc + step_val;
    end

endmodule
