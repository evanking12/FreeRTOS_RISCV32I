`timescale 1ns / 1ps

module decoder (
    input  wire [31:0] instr,

    output wire [4:0]  rd,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    output wire [31:0] imm,

    output wire        is_addi,
    output wire        is_add,
    output wire        is_sub,
    output wire        is_and,
    output wire        is_or,
    output wire        is_xor,
    output wire        is_xori,
    output wire        is_ori,
    output wire        is_andi,
    output wire        is_slti,
    output wire        is_sltiu,
    output wire        is_slli,
    output wire        is_srli,
    output wire        is_srai,
    output wire [1:0]  alu_op,

    output wire        is_branch,
    output wire        is_beq,
    output wire        is_bne,
    output wire [31:0] imm_B,

    output wire        is_lw,
    output wire        is_sw,
    output wire [31:0] imm_S,

    output wire        is_jal,
    output wire        is_jalr,
    output wire [31:0] imm_J,
    
    output wire [31:0] imm_U,
    output wire        is_lui,
    output wire        is_auipc,

    output wire is_blt,
    output wire is_bge,
    output wire is_bltu,
    output wire is_bgeu,
    output wire is_lb,
    output wire is_lh,
    output wire is_lbu,
    output wire is_lhu,
    output wire is_sb,
    output wire is_sh,
    output wire is_fence,
    output wire is_ecall,
    output wire is_ebreak,
    output wire is_csr_op,
    output wire [11:0] csr_addr,
    output wire [2:0] csr_funct3,
    output wire [4:0] csr_zimm,
    
    // R-type compare and shift
    output wire        is_slt,
    output wire        is_sltu,
    output wire        is_sll,
    output wire        is_srl,
    output wire        is_sra
);

    //----------------------------------------
    // FIELD EXTRACTION
    //----------------------------------------
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    //----------------------------------------
    // IMMEDIATE (I-type, for ADDI)
    //----------------------------------------
    assign imm = {{20{instr[31]}}, instr[31:20]};

    //----------------------------------------
    // OPCODE CHECKS
    //----------------------------------------
    wire [6:0] opcode = instr[6:0];

    wire is_rtype = (opcode == 7'b0110011);   // ADD, SUB, AND, OR, XOR, etc.
    wire is_itype = (opcode == 7'b0010011); // ADDI, ANDI, ORI, etc.
    
    
    assign is_lw  = (opcode == 7'b0000011) && (funct3 == 3'b010);
    assign is_sw  = (opcode == 7'b0100011) && (funct3 == 3'b010);
    assign is_jal = (opcode == 7'b1101111);
    assign is_jalr= (opcode == 7'b1100111) && (funct3 == 3'b000);


    assign imm_J = {{12{instr[31]}},
                    instr[19:12],
                    instr[20],
                    instr[30:21],
                    1'b0};

    
    assign is_addi = is_itype && (funct3 == 3'b000);
    assign is_add  = is_rtype && (funct3 == 3'b000) && (funct7 == 7'b0000000);
    assign is_sub  = is_rtype && (funct3 == 3'b000) && (funct7 == 7'b0100000);
    assign is_and  = is_rtype && (funct3 == 3'b111);
    assign is_or   = is_rtype && (funct3 == 3'b110);
    assign is_xor  = is_rtype && (funct3 == 3'b100);
    assign is_xori = is_itype && (funct3 == 3'b100);  
    assign is_ori  = is_itype && (funct3 == 3'b110);  
    assign is_andi = is_itype && (funct3 == 3'b111);  
    assign is_slti  = is_itype && (funct3 == 3'b010);
    assign is_sltiu = is_itype && (funct3 == 3'b011);
    assign is_slli = is_itype && (funct3 == 3'b001) && (instr[31:25] == 7'b0000000);
    assign is_srli = is_itype && (funct3 == 3'b101) && (instr[31:25] == 7'b0000000);
    assign is_srai = is_itype && (funct3 == 3'b101) && (instr[31:25] == 7'b0100000);
    // R-type compare and shift instructions
    assign is_slt  = is_rtype && (funct3 == 3'b010) && (funct7 == 7'b0000000);
    assign is_sltu = is_rtype && (funct3 == 3'b011) && (funct7 == 7'b0000000);
    assign is_sll  = is_rtype && (funct3 == 3'b001) && (funct7 == 7'b0000000);
    assign is_srl  = is_rtype && (funct3 == 3'b101) && (funct7 == 7'b0000000);
    assign is_sra  = is_rtype && (funct3 == 3'b101) && (funct7 == 7'b0100000);
    assign imm_U = { instr[31:12], 12'b0 };
    assign is_lui = (opcode == 7'b0110111);
    assign is_auipc = (opcode == 7'b0010111);
    assign is_blt  = is_branch && (funct3 == 3'b100);
    assign is_bge  = is_branch && (funct3 == 3'b101);
    assign is_bltu = is_branch && (funct3 == 3'b110);
    assign is_bgeu = is_branch && (funct3 == 3'b111);
    
        // LOADS (opcode = 0000011)
    assign is_lb  = (opcode == 7'b0000011) && (funct3 == 3'b000);
    assign is_lh  = (opcode == 7'b0000011) && (funct3 == 3'b001);
    assign is_lbu = (opcode == 7'b0000011) && (funct3 == 3'b100);
    assign is_lhu = (opcode == 7'b0000011) && (funct3 == 3'b101);
    
    // STORES (opcode = 0100011)
    assign is_sb  = (opcode == 7'b0100011) && (funct3 == 3'b000);
    assign is_sh  = (opcode == 7'b0100011) && (funct3 == 3'b001);
    
    // SYSTEM (opcode = 1110011)
    wire is_system_opcode = (opcode == 7'b1110011);
    
    assign is_ecall  = is_system_opcode &&
                       (instr[31:20] == 12'h000) &&
                       (funct3 == 3'b000) &&
                       (rs1 == 5'b00000) &&
                       (rd  == 5'b00000);
    
    assign is_ebreak = is_system_opcode &&
                       (instr[31:20] == 12'h001) &&
                       (funct3 == 3'b000) &&
                       (rs1 == 5'b00000) &&
                       (rd  == 5'b00000);
    assign is_csr_op   = is_system_opcode && (funct3 != 3'b000);
    assign csr_addr    = instr[31:20];
    assign csr_funct3  = funct3;
    assign csr_zimm    = instr[19:15];
    
    // FENCE  (opcode = 0001111)
    assign is_fence  = (opcode == 7'b0001111);

    assign imm_S = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    
    assign imm_B = {{20{instr[31]}},
                    instr[7],
                    instr[30:25],
                    instr[11:8],
                    1'b0};
    
    assign is_branch = (opcode == 7'b1100011);
    assign is_beq    = is_branch && (funct3 == 3'b000);
    assign is_bne    = is_branch && (funct3 == 3'b001);
    
    localparam ALU_ADD  = 2'b00;
    localparam ALU_ADDI = 2'b01;
    localparam ALU_SUB  = 2'b10;
    localparam ALU_LOGIC= 2'b11;
    
    assign alu_op =
          is_addi ? ALU_ADDI :
          is_add  ? ALU_ADD  :
          is_sub  ? ALU_SUB  :
          (is_and  | is_or   | is_xor  |
           is_xori | is_ori  | is_andi |
           is_slti | is_sltiu| is_slli |
           is_srli | is_srai |
           is_slt  | is_sltu | is_sll  |
           is_srl  | is_sra) ? ALU_LOGIC :
          ALU_ADD;

endmodule
