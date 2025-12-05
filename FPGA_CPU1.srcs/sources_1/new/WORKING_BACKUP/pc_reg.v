`timescale 1ns / 1ps

// pc_reg.v
module pc_reg(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pc_en,           // hold PC when 0
    input  wire        branch_flag,     // 1 = take branch
    input  wire [31:0] branch_target,   // where to jump
    output reg  [31:0] pc
);
    // CRITICAL: Use async reset to match if_id latch timing!
    // Without this, PC increments to 4 before if_id can capture PC=0
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'b0;     // reset to 0 (async!)
        end
        else if (!pc_en) begin
            pc <= pc;        // hold
        end
        else if (branch_flag) begin
            pc <= branch_target;   // jump
        end
        else begin
            pc <= pc + 32'd4;      // normal sequential PC
        end
    end
endmodule
