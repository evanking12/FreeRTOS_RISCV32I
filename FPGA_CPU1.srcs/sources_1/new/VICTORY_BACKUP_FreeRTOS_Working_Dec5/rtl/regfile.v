`timescale 1ns / 1ps

module regfile (
    input  wire        clk,
    input  wire        we,        // write enable
    input  wire [4:0]  rs1,       // read register 1
    input  wire [4:0]  rs2,       // read register 2
    input  wire [4:0]  rd,        // write register
    input  wire [31:0] wd,        // write data

    output wire [31:0] rs1_val,
    output wire [31:0] rs2_val
);

    reg [31:0] regs [0:31];

    // Initialize all registers to 0 for simulation
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'h0;
    end

    // Write port
    always @(posedge clk) begin
        if (we && rd != 0)
            regs[rd] <= wd;
    end

    // Read ports (x0 always returns 0)
    assign rs1_val = (rs1 == 0) ? 32'b0 : regs[rs1];
    assign rs2_val = (rs2 == 0) ? 32'b0 : regs[rs2];

endmodule
