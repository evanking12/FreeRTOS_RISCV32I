`timescale 1ns / 1ps

// Simple IF/ID pipeline latch with branch flush
module if_id(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hold,       // hold current contents when 1
    input  wire        flush,      // asserted on branch/jump
    input  wire [31:0] if_pc,
    input  wire [31:0] if_inst,
    output reg  [31:0] id_pc,
    output reg  [31:0] id_inst
);
    // Hold has priority over normal advance; flush clears the latch.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc   <= 32'b0;
            id_inst <= 32'b0;
        end else if (flush) begin
            id_pc   <= 32'b0;
            id_inst <= 32'b0;
        end else if (!hold) begin
            id_pc   <= if_pc;
            id_inst <= if_inst;
        end
        // when hold==1, retain previous id_pc/id_inst
    end
endmodule
