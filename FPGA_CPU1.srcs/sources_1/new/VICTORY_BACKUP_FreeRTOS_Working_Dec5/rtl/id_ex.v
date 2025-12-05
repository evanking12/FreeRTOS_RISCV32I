`timescale 1ns / 1ps

// ID/EX -> MEM/WB latch for the 3-stage pipeline
module id_ex(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hold,          // hold previous contents when 1 (external stall)
    input  wire        bubble,        // when 1, insert NOP/bubble into EX (hazard)
    // Inputs from ID/EX stage
    input  wire [4:0]  id_rd,
    input  wire        id_we,
    input  wire [31:0] id_alu_res,
    input  wire [31:0] id_store_data,
    input  wire        id_is_lb,
    input  wire        id_is_lh,
    input  wire        id_is_lw,
    input  wire        id_is_lbu,
    input  wire        id_is_lhu,
    input  wire        id_is_sb,
    input  wire        id_is_sh,
    input  wire        id_is_sw,
    input  wire        id_is_jal,
    input  wire        id_is_jalr,
    input  wire        id_is_lui,
    input  wire        id_is_auipc,
    input  wire [31:0] id_link_value,
    input  wire [31:0] id_auipc_value,
    input  wire [31:0] id_lui_value,
    input  wire        id_is_csr,
    input  wire [11:0] id_csr_addr,
    input  wire [2:0]  id_csr_funct3,
    input  wire [4:0]  id_csr_zimm,
    input  wire [31:0] id_csr_rs1,
    input  wire        id_branch_flag,
    input  wire [31:0] id_branch_target,
    input  wire [31:0] id_pc,
    input  wire [31:0] id_imm_B,
    input  wire [31:0] id_imm_J,
    input  wire [31:0] id_imm_I,
    input  wire        id_is_beq,
    input  wire        id_is_bne,
    input  wire        id_is_blt,
    input  wire        id_is_bge,
    input  wire        id_is_bltu,
    input  wire        id_is_bgeu,
    input  wire        id_is_branch_dec,
    input  wire [31:0] id_op1,
    input  wire [31:0] id_op2,
    // Outputs to MEM/WB stage
    output reg  [4:0]  ex_rd,
    output reg         ex_we,
    output reg  [31:0] ex_alu_res,
    output reg  [31:0] ex_store_data,
    output reg         ex_is_lb,
    output reg         ex_is_lh,
    output reg         ex_is_lw,
    output reg         ex_is_lbu,
    output reg         ex_is_lhu,
    output reg         ex_is_sb,
    output reg         ex_is_sh,
    output reg         ex_is_sw,
    output reg         ex_is_jal,
    output reg         ex_is_jalr,
    output reg         ex_is_lui,
    output reg         ex_is_auipc,
    output reg  [31:0] ex_link_value,
    output reg  [31:0] ex_auipc_value,
    output reg  [31:0] ex_lui_value,
    output reg         ex_is_csr,
    output reg  [11:0] ex_csr_addr,
    output reg  [2:0]  ex_csr_funct3,
    output reg  [4:0]  ex_csr_zimm,
    output reg  [31:0] ex_csr_rs1,
    output reg         ex_branch_flag,
    output reg  [31:0] ex_branch_target,
    output reg  [31:0] ex_pc,
    output reg  [31:0] ex_imm_B,
    output reg  [31:0] ex_imm_J,
    output reg  [31:0] ex_imm_I,
    output reg         ex_is_beq,
    output reg         ex_is_bne,
    output reg         ex_is_blt,
    output reg         ex_is_bge,
    output reg         ex_is_bltu,
    output reg         ex_is_bgeu,
    output reg         ex_is_branch_dec,
    output reg  [31:0] ex_op1,
    output reg  [31:0] ex_op2
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_rd          <= 5'b0;
            ex_we          <= 1'b0;
            ex_alu_res     <= 32'b0;
            ex_store_data  <= 32'b0;
            ex_is_lb       <= 1'b0;
            ex_is_lh       <= 1'b0;
            ex_is_lw       <= 1'b0;
            ex_is_lbu      <= 1'b0;
            ex_is_lhu      <= 1'b0;
            ex_is_sb       <= 1'b0;
            ex_is_sh       <= 1'b0;
            ex_is_sw       <= 1'b0;
            ex_is_jal      <= 1'b0;
            ex_is_jalr     <= 1'b0;
            ex_is_lui      <= 1'b0;
            ex_is_auipc    <= 1'b0;
            ex_link_value  <= 32'b0;
            ex_auipc_value <= 32'b0;
            ex_lui_value   <= 32'b0;
            ex_is_csr      <= 1'b0;
            ex_csr_addr    <= 12'b0;
            ex_csr_funct3  <= 3'b0;
            ex_csr_zimm    <= 5'b0;
            ex_csr_rs1     <= 32'b0;
            ex_branch_flag   <= 1'b0;
            ex_branch_target <= 32'b0;
            ex_pc            <= 32'b0;
            ex_imm_B         <= 32'b0;
            ex_imm_J         <= 32'b0;
            ex_imm_I         <= 32'b0;
            ex_is_beq        <= 1'b0;
            ex_is_bne        <= 1'b0;
            ex_is_blt        <= 1'b0;
            ex_is_bge        <= 1'b0;
            ex_is_bltu       <= 1'b0;
            ex_is_bgeu       <= 1'b0;
            ex_is_branch_dec <= 1'b0;
            ex_op1           <= 32'b0;
            ex_op2           <= 32'b0;
        end else if (hold) begin
            // keep current contents when stalling
        end else if (bubble) begin
            ex_rd          <= 5'b0;
            ex_we          <= 1'b0;
            ex_alu_res     <= 32'b0;
            ex_store_data  <= 32'b0;
            ex_is_lb       <= 1'b0;
            ex_is_lh       <= 1'b0;
            ex_is_lw       <= 1'b0;
            ex_is_lbu      <= 1'b0;
            ex_is_lhu      <= 1'b0;
            ex_is_sb       <= 1'b0;
            ex_is_sh       <= 1'b0;
            ex_is_sw       <= 1'b0;
            ex_is_jal      <= 1'b0;
            ex_is_jalr     <= 1'b0;
            ex_is_lui      <= 1'b0;
            ex_is_auipc    <= 1'b0;
            ex_link_value  <= 32'b0;
            ex_auipc_value <= 32'b0;
            ex_lui_value   <= 32'b0;
            ex_is_csr      <= 1'b0;
            ex_csr_addr    <= 12'b0;
            ex_csr_funct3  <= 3'b0;
            ex_csr_zimm    <= 5'b0;
            ex_csr_rs1     <= 32'b0;
            ex_branch_flag   <= 1'b0;
            ex_branch_target <= 32'b0;
            ex_pc            <= 32'b0;
            ex_imm_B         <= 32'b0;
            ex_imm_J         <= 32'b0;
            ex_imm_I         <= 32'b0;
            ex_is_beq        <= 1'b0;
            ex_is_bne        <= 1'b0;
            ex_is_blt        <= 1'b0;
            ex_is_bge        <= 1'b0;
            ex_is_bltu       <= 1'b0;
            ex_is_bgeu       <= 1'b0;
            ex_is_branch_dec <= 1'b0;
            ex_op1           <= 32'b0;
            ex_op2           <= 32'b0;
        end else begin
            ex_rd          <= id_rd;
            ex_we          <= id_we;
            ex_alu_res     <= id_alu_res;
            ex_store_data  <= id_store_data;
            ex_is_lb       <= id_is_lb;
            ex_is_lh       <= id_is_lh;
            ex_is_lw       <= id_is_lw;
            ex_is_lbu      <= id_is_lbu;
            ex_is_lhu      <= id_is_lhu;
            ex_is_sb       <= id_is_sb;
            ex_is_sh       <= id_is_sh;
            ex_is_sw       <= id_is_sw;
            ex_is_jal      <= id_is_jal;
            ex_is_jalr     <= id_is_jalr;
            ex_is_lui      <= id_is_lui;
            ex_is_auipc    <= id_is_auipc;
            ex_link_value  <= id_link_value;
            ex_auipc_value <= id_auipc_value;
            ex_lui_value   <= id_lui_value;
            ex_is_csr      <= id_is_csr;
            ex_csr_addr    <= id_csr_addr;
            ex_csr_funct3  <= id_csr_funct3;
            ex_csr_zimm    <= id_csr_zimm;
            ex_csr_rs1     <= id_csr_rs1;
            ex_branch_flag   <= id_branch_flag;
            ex_branch_target <= id_branch_target;
            ex_pc            <= id_pc;
            ex_imm_B         <= id_imm_B;
            ex_imm_J         <= id_imm_J;
            ex_imm_I         <= id_imm_I;
            ex_is_beq        <= id_is_beq;
            ex_is_bne        <= id_is_bne;
            ex_is_blt        <= id_is_blt;
            ex_is_bge        <= id_is_bge;
            ex_is_bltu       <= id_is_bltu;
            ex_is_bgeu       <= id_is_bgeu;
            ex_is_branch_dec <= id_is_branch_dec;
            ex_op1           <= id_op1;
            ex_op2           <= id_op2;
        end
    end
endmodule
