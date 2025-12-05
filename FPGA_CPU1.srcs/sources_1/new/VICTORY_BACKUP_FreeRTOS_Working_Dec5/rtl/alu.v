`timescale 1ns / 1ps

module alu (
    input  wire [31:0] rs1_val,
    input  wire [31:0] rs2_val,
    input  wire [31:0] imm,
    input  wire [1:0]  alu_op,
    input wire [6:0] funct7,
    input  wire [2:0] funct3,   
    output reg  [31:0] result
);
    localparam ALU_ADD    = 2'b00;
    localparam ALU_ADDI   = 2'b01;
    localparam ALU_SUB    = 2'b10;
    localparam ALU_LOGIC  = 2'b11;

    always @(*) begin
        case (alu_op)
            ALU_ADDI: result = rs1_val + imm;
            ALU_ADD : result = rs1_val + rs2_val;
            ALU_SUB : result = rs1_val - rs2_val;
            ALU_LOGIC: begin
                case (funct3)
                    3'b111: result = rs1_val & rs2_val; // AND / ANDI
                    3'b110: result = rs1_val | rs2_val; // OR / ORI
                    3'b100: result = rs1_val ^ rs2_val; // XOR / XORI
                    3'b010: result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'b1 : 32'b0; // SLT / SLTI
                    3'b011: result = (rs1_val < rs2_val) ? 32'b1 : 32'b0;                   // SLTU / SLTIU
                    3'b001: result = rs1_val << rs2_val[4:0];                     // SLL / SLLI
                    3'b101: begin // SRL / SRLI / SRA / SRAI
                        if (funct7[5] == 1'b0)
                            result = rs1_val >> rs2_val[4:0];                     // Logical shift
                        else
                            result = $signed($signed(rs1_val) >>> rs2_val[4:0]); // Arithmetic shift
                    end
                    default: result = 32'b0;
                endcase
            end
            default: result = 32'b0;
        endcase
    end

endmodule
