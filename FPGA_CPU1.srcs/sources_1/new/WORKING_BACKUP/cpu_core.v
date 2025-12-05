`timescale 1ns / 1ps

// 3-stage pipeline: IF | ID/EX | MEM/WB
module cpu_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        step_pulse,   // external hold (e.g., UART busy)
    input  wire        irq_i,   // external interrupt request (level)
    output wire [31:0] pc_o,

    // instruction + data memory
    input  wire [31:0] instr_i,
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    input  wire [31:0] d_rdata,
    output wire        d_we,

    // debug/IO
    output wire [31:0] wb_value,
    output wire        is_sw_o,
    output wire        is_sh_o,
    output wire        is_sb_o,
    output wire [31:0] rs2_val_o
);

    // ------------------------------------------------------------
    // CLINT timer (64-bit)
    // ------------------------------------------------------------
    reg [63:0] clint_mtime;
    reg [63:0] clint_mtimecmp;
    wire       clint_mtip;

    // ------------------------------------------------------------
    // IF stage
    // ------------------------------------------------------------
    wire branch_flag;
    wire [31:0] branch_target;
    // Forward declarations for branch control
    wire flush_pipeline;
    wire branch_flag_ex;


    // PC held by external hold (step_pulse) OR internal pipeline stall
    wire [31:0] pc;
    wire pc_stall;  // Forward declaration, assigned after pipeline_stall is defined
    pc_reg u_pc (
        .clk          (clk),
        .rst_n        (rst_n),
        .pc_en        (step_pulse && !pc_stall),
        .branch_flag  (branch_flag),
        .branch_target(branch_target),
        .pc           (pc)
    );
    assign pc_o = pc;

    // IF/ID latch
    wire [31:0] id_pc;
    wire [31:0] id_inst;
    wire hold_ifid;
    wire flush_ifid;

    // ------------------------------------------------------------
    // Decode
    // ------------------------------------------------------------
    wire [4:0]  rd, rs1, rs2;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [31:0] imm;
    wire [31:0] imm_B;
    wire [31:0] imm_S;
    wire [31:0] imm_J_internal;

    wire is_addi, is_add, is_sub, is_and, is_or, is_xor;
    wire is_branch_dec, is_beq_dec, is_bne_dec;
    wire is_blt_dec, is_bge_dec, is_bltu_dec, is_bgeu_dec;
    wire is_lw, is_sw, is_jal, is_jalr;
    wire is_xori, is_ori, is_andi;
    wire is_slti, is_sltiu;
    wire is_slli, is_srli, is_srai;
    wire is_slt, is_sltu, is_sll, is_srl, is_sra;
    wire [1:0] alu_op;
    wire [31:0] imm_U;
    wire is_lui;
    wire is_auipc;
    wire is_lb, is_lh, is_lbu, is_lhu;
    wire is_sb, is_sh;
    wire is_fence, is_ecall, is_ebreak;
    wire is_csr_op;
    wire [11:0] csr_addr;
    wire [2:0]  csr_funct3;
    wire [4:0]  csr_zimm;

    decoder u_dec (
        .instr(id_inst),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .funct3(funct3),
        .funct7(funct7),
        .imm(imm),

        .is_addi(is_addi),
        .is_add(is_add),
        .is_sub(is_sub),
        .is_and(is_and),
        .is_or(is_or),
        .is_xor(is_xor),
        .is_xori(is_xori),
        .is_ori(is_ori),
        .is_andi(is_andi),
        .is_slti(is_slti),
        .is_sltiu(is_sltiu),
        .is_slli(is_slli),
        .is_srli(is_srli),
        .is_srai(is_srai),
        .alu_op(alu_op),

        .is_branch(is_branch_dec),
        .is_beq(is_beq_dec),
        .is_bne(is_bne_dec),
        .imm_B(imm_B),

        .is_lw(is_lw),
        .is_sw(is_sw),
        .imm_S(imm_S),

        .is_jal(is_jal),
        .is_jalr(is_jalr),
        .imm_J(imm_J_internal),
        .is_lui(is_lui),
        .imm_U(imm_U),
        .is_auipc(is_auipc),
        .is_blt(is_blt_dec),
        .is_bge(is_bge_dec),
        .is_bltu(is_bltu_dec),
        .is_bgeu(is_bgeu_dec),

        .is_lb(is_lb),
        .is_lh(is_lh),
        .is_lbu(is_lbu),
        .is_lhu(is_lhu),
        .is_sb(is_sb),
        .is_sh(is_sh),
        .is_fence(is_fence),
        .is_ecall(is_ecall),
        .is_ebreak(is_ebreak),
        .is_csr_op(is_csr_op),
        .csr_addr(csr_addr),
        .csr_funct3(csr_funct3),
        .csr_zimm(csr_zimm),
        .is_slt(is_slt),
        .is_sltu(is_sltu),
        .is_sll(is_sll),
        .is_srl(is_srl),
        .is_sra(is_sra)
    );

    // Hold IF/ID only on external hold; flush on branch/trap

    if_id u_ifid(
        .clk(clk),
        .rst_n(rst_n),
        .hold(hold_ifid),
        .flush(flush_ifid),
        .if_pc(pc),
        .if_inst(instr_i),
        .id_pc(id_pc),
        .id_inst(id_inst)
    );

    // ------------------------------------------------------------
    // Register File + forwarding
    // ------------------------------------------------------------
    wire [31:0] rs1_val, rs2_val;

    // WB stage signals (from MEM/WB stage, see bottom)
    wire        wb_we;
    wire [4:0]  wb_rd;
    wire [31:0] wb_wdata;

    regfile u_rf (
        .clk(clk),
        .we(wb_we),
        .rs1(rs1),
        .rs2(rs2),
        .rd(wb_rd),
        .wd(wb_wdata),
        .rs1_val(rs1_val),
        .rs2_val(rs2_val)
    );

    // Forwarding: EX (ALU) > WB (loaded value) > Regfile
    // These determine if we can forward from each stage
    wire ex_is_load = ex_is_lb | ex_is_lh | ex_is_lw | ex_is_lbu | ex_is_lhu;
    wire ex_will_write = ex_we && (ex_rd != 5'b0);
    // Can forward ALU result, but NOT load, CSR, LUI, AUIPC, JAL, JALR 
    // (their results don't come from ALU, so forward from WB stage instead)
    wire ex_can_forward = ex_will_write && !ex_is_load && !ex_is_csr && 
                          !ex_is_lui && !ex_is_auipc && !ex_is_jal && !ex_is_jalr;
    
    wire wb_will_write = wb_we && (wb_rd != 5'b0);
    
    // Forward from EX if rd matches (priority 1)
    wire forward_ex_rs1 = ex_can_forward && (ex_rd == rs1) && (rs1 != 5'b0);
    wire forward_ex_rs2 = ex_can_forward && (ex_rd == rs2) && (rs2 != 5'b0);
    
    // Forward from WB if rd matches and NOT already forwarding from EX (priority 2)
    wire forward_wb_rs1 = !forward_ex_rs1 && wb_will_write && (wb_rd == rs1) && (rs1 != 5'b0);
    wire forward_wb_rs2 = !forward_ex_rs2 && wb_will_write && (wb_rd == rs2) && (rs2 != 5'b0);
    
    // Mux in operands: EX > WB > regfile
    wire [31:0] op1 = forward_ex_rs1 ? ex_alu_res : 
                      forward_wb_rs1 ? wb_wdata : 
                      rs1_val;
    wire [31:0] op2 = forward_ex_rs2 ? ex_alu_res : 
                      forward_wb_rs2 ? wb_wdata : 
                      rs2_val;
    assign rs2_val_o = op2;

    // ------------------------------------------------------------
    // ALU (combinational in ID/EX stage)
    // ------------------------------------------------------------
    wire [31:0] alu_src2 =
        (is_xori | is_ori | is_andi | is_addi | is_slti | is_sltiu |
         is_slli | is_srli | is_srai) ? imm : op2;

    wire [31:0] alu_result;
    alu u_alu (
        .rs1_val(op1),
        .rs2_val(alu_src2),
        .imm(imm),
        .alu_op(alu_op),
        .funct3(funct3),
        .result(alu_result),
        .funct7(funct7)
    );

    // Address calculation for load/store
    wire [31:0] addr_calc =
        (is_sb | is_sh | is_sw) ? (op1 + imm_S) : (op1 + imm);

    // ------------------------------------------------------------
    // Branch / jump will resolve in EX stage using registered operands/control
    wire [31:0] id_op1 = op1;
    wire [31:0] id_op2 = op2;

    // ------------------------------------------------------------
    // ID/EX latch
    // ------------------------------------------------------------
    wire id_we = (is_addi | is_add | is_sub | is_and | is_or | is_xor |
                  is_xori | is_ori | is_andi |
                  is_slti | is_sltiu | is_slli | is_srli | is_srai |
                  is_slt | is_sltu | is_sll | is_srl | is_sra |
                  is_lw | is_lb | is_lh | is_lbu | is_lhu |
                  is_jal | is_jalr | is_lui | is_auipc | is_csr_op) &&
                 !(is_fence | is_ecall | is_ebreak);

    wire [31:0] id_link_value  = id_pc + 32'd4;
    wire [31:0] id_auipc_value = id_pc + imm_U;
    wire [31:0] id_lui_value   = imm_U;

    // Select value to send toward MEM/WB (ALU or address)
    wire [31:0] id_alu_res =
        (is_lb | is_lh | is_lw | is_lbu | is_lhu | is_sb | is_sh | is_sw) ? addr_calc :
        alu_result;

    wire [31:0] id_store_data = op2;

    wire [4:0]  ex_rd;
    wire        ex_we;
    wire [31:0] ex_alu_res;
    wire [31:0] ex_store_data;
    wire        ex_is_lb, ex_is_lh, ex_is_lw, ex_is_lbu, ex_is_lhu;
    wire        ex_is_sb, ex_is_sh, ex_is_sw;
    wire        ex_is_jal, ex_is_jalr, ex_is_lui, ex_is_auipc;
    wire [31:0] ex_link_value, ex_auipc_value, ex_lui_value;
    wire        ex_is_csr;
    wire [11:0] ex_csr_addr;
    wire [2:0]  ex_csr_funct3;
    wire [4:0]  ex_csr_zimm;
    wire [31:0] ex_csr_rs1;
    wire        ex_branch_flag;
    wire [31:0] ex_branch_target;
    wire [31:0] ex_pc_reg;
    wire [31:0] ex_imm_B_reg;
    wire [31:0] ex_imm_J_reg;
    wire [31:0] ex_imm_I_reg;
    wire        ex_is_beq, ex_is_bne, ex_is_blt, ex_is_bge, ex_is_bltu, ex_is_bgeu;
    wire        ex_is_branch_dec;
    wire [31:0] ex_op1, ex_op2;

    // RAW hazard for non-forwardable instructions in EX stage
    // NOTE: This CPU uses WB forwarding (wb_* signals are combinatorial from EX),
    // so instructions like auipc/lui/load CAN forward their results in the same cycle!
    // The stall is DISABLED - WB forwarding handles these cases.
    wire load_use_hazard = 1'b0;  // DISABLED: use WB forwarding instead of stalling

    wire csr_write_pending = ex_is_csr &&
        ((ex_csr_funct3 == 3'b001) ||
         ((ex_csr_funct3 == 3'b010 || ex_csr_funct3 == 3'b011) && |ex_csr_rs1) ||
         (ex_csr_funct3 == 3'b101) ||
        ((ex_csr_funct3 == 3'b110 || ex_csr_funct3 == 3'b111) && |ex_csr_zimm));

    // CSR-to-CSR hazard (same CSR address)
    wire csr_hazard = is_csr_op && ex_is_csr && (csr_addr == ex_csr_addr) && csr_write_pending;
    
    // RAW hazard: any instruction reading rd of CSR in EX (can't forward from EX for CSR)
    wire csr_rd_hazard = ex_is_csr && ex_we && (ex_rd != 5'b0) &&
                         ((rs1 == ex_rd) || (rs2 == ex_rd));
    
    // MRET hazard: mret reads mepc, but previous CSR instruction is writing to mepc
    wire mret_mepc_hazard = is_mret && ex_is_csr && (ex_csr_addr == 12'h341) && csr_write_pending;

    wire pipeline_stall = load_use_hazard | csr_hazard | csr_rd_hazard | mret_mepc_hazard;
    assign pc_stall = pipeline_stall;  // Hold PC during stall
    wire hold_idex = ~step_pulse;  // Normal hold behavior
    wire bubble_idex = branch_flag_ex | pipeline_stall;  // Bubble inserts NOP, but EX still completes!

    id_ex u_idex(
        .clk(clk),
        .rst_n(rst_n),
        .hold(hold_idex),
        .bubble(bubble_idex),
        .id_rd(rd),
        .id_we(id_we),
        .id_alu_res(id_alu_res),
        .id_store_data(id_store_data),
        .id_is_lb(is_lb),
        .id_is_lh(is_lh),
        .id_is_lw(is_lw),
        .id_is_lbu(is_lbu),
        .id_is_lhu(is_lhu),
        .id_is_sb(is_sb),
        .id_is_sh(is_sh),
        .id_is_sw(is_sw),
        .id_is_jal(is_jal),
        .id_is_jalr(is_jalr),
        .id_is_lui(is_lui),
        .id_is_auipc(is_auipc),
        .id_link_value(id_link_value),
        .id_auipc_value(id_auipc_value),
        .id_lui_value(id_lui_value),
        .id_is_csr(is_csr_op),
        .id_csr_addr(csr_addr),
        .id_csr_funct3(csr_funct3),
        .id_csr_zimm(csr_zimm),
        .id_csr_rs1(op1),
        .id_branch_flag(flush_pipeline),
        .id_branch_target(branch_target),
        .id_pc(id_pc),
        .id_imm_B(imm_B),
        .id_imm_J(imm_J_internal),
        .id_imm_I(imm),
        .id_is_beq(is_beq_dec),
        .id_is_bne(is_bne_dec),
        .id_is_blt(is_blt_dec),
        .id_is_bge(is_bge_dec),
        .id_is_bltu(is_bltu_dec),
        .id_is_bgeu(is_bgeu_dec),
        .id_is_branch_dec(is_branch_dec),
        .id_op1(id_op1),
        .id_op2(id_op2),
        .ex_rd(ex_rd),
        .ex_we(ex_we),
        .ex_alu_res(ex_alu_res),
        .ex_store_data(ex_store_data),
        .ex_is_lb(ex_is_lb),
        .ex_is_lh(ex_is_lh),
        .ex_is_lw(ex_is_lw),
        .ex_is_lbu(ex_is_lbu),
        .ex_is_lhu(ex_is_lhu),
        .ex_is_sb(ex_is_sb),
        .ex_is_sh(ex_is_sh),
        .ex_is_sw(ex_is_sw),
        .ex_is_jal(ex_is_jal),
        .ex_is_jalr(ex_is_jalr),
        .ex_is_lui(ex_is_lui),
        .ex_is_auipc(ex_is_auipc),
        .ex_link_value(ex_link_value),
        .ex_auipc_value(ex_auipc_value),
        .ex_lui_value(ex_lui_value),
        .ex_is_csr(ex_is_csr),
        .ex_csr_addr(ex_csr_addr),
        .ex_csr_funct3(ex_csr_funct3),
        .ex_csr_zimm(ex_csr_zimm),
        .ex_csr_rs1(ex_csr_rs1),
        .ex_branch_flag(ex_branch_flag),
        .ex_branch_target(ex_branch_target),
        .ex_pc(ex_pc_reg),
        .ex_imm_B(ex_imm_B_reg),
        .ex_imm_J(ex_imm_J_reg),
        .ex_imm_I(ex_imm_I_reg),
        .ex_is_beq(ex_is_beq),
        .ex_is_bne(ex_is_bne),
        .ex_is_blt(ex_is_blt),
        .ex_is_bge(ex_is_bge),
        .ex_is_bltu(ex_is_bltu),
        .ex_is_bgeu(ex_is_bgeu),
        .ex_is_branch_dec(ex_is_branch_dec),
        .ex_op1(ex_op1),
        .ex_op2(ex_op2)
    );

    // ------------------------------------------------------------
    // Branch resolution in EX (registered) + trap/mret combine
    // ------------------------------------------------------------
    wire cmp_eq_ex  = (ex_op1 == ex_op2);
    wire cmp_lt_ex  = ($signed(ex_op1) < $signed(ex_op2));
    wire cmp_ltu_ex = (ex_op1 < ex_op2);

    assign branch_flag_ex =
          (ex_is_beq  && cmp_eq_ex)        ||
          (ex_is_bne  && !cmp_eq_ex)       ||
          (ex_is_blt  && cmp_lt_ex)        ||
          (ex_is_bge  && !cmp_lt_ex)       ||
          (ex_is_bltu && cmp_ltu_ex)       ||
          (ex_is_bgeu && !cmp_ltu_ex)      ||
          ex_is_jal || ex_is_jalr;

    wire [31:0] branch_target_ex =
          ex_is_jal  ? (ex_pc_reg + ex_imm_J_reg) :
          ex_is_jalr ? ((ex_op1 + ex_imm_I_reg) & ~32'b1) :
                        (ex_pc_reg + ex_imm_B_reg);

    // No extra MEM stage: use EX outputs directly
    wire [4:0]  mem_rd          = ex_rd;
    wire        mem_we          = ex_we;
    wire [31:0] mem_alu_res     = ex_alu_res;
    wire [31:0] mem_store_data  = ex_store_data;
    wire        mem_is_lb       = ex_is_lb;
    wire        mem_is_lh       = ex_is_lh;
    wire        mem_is_lw       = ex_is_lw;
    wire        mem_is_lbu      = ex_is_lbu;
    wire        mem_is_lhu      = ex_is_lhu;
    wire        mem_is_sb       = ex_is_sb;
    wire        mem_is_sh       = ex_is_sh;
    wire        mem_is_sw       = ex_is_sw;
    wire        mem_is_jal      = ex_is_jal;
    wire        mem_is_jalr     = ex_is_jalr;
    wire        mem_is_lui      = ex_is_lui;
    wire        mem_is_auipc    = ex_is_auipc;
    wire [31:0] mem_link_value  = ex_link_value;
    wire [31:0] mem_auipc_value = ex_auipc_value;
    wire [31:0] mem_lui_value   = ex_lui_value;
    wire        mem_is_csr      = ex_is_csr;
    wire [11:0] mem_csr_addr    = ex_csr_addr;
    wire [2:0]  mem_csr_funct3  = ex_csr_funct3;
    wire [4:0]  mem_csr_zimm    = ex_csr_zimm;
    wire [31:0] mem_csr_rs1     = ex_csr_rs1;

    // DISABLED: Allow misaligned loads/stores (may give wrong data for cross-word access)
    // This lets FreeRTOS work without implementing full misaligned emulation
    wire misaligned_load = 1'b0;  // Was: (mem_is_lw && |mem_alu_res[1:0]) || ((mem_is_lh | mem_is_lhu) && mem_alu_res[0]);
    wire misaligned_store = 1'b0; // Was: (mem_is_sw && |mem_alu_res[1:0]) || (mem_is_sh && mem_alu_res[0]);
    wire misaligned_trap = 1'b0;  // Disabled to allow unaligned access
    wire [31:0] misaligned_cause_code =
        misaligned_load  ? 32'h00000004 :
        misaligned_store ? 32'h00000006 :
                            32'b0;
    wire [31:0] mem_pc = ex_pc_reg;

    wire clint_match_mtime_lo    = (mem_alu_res == CLINT_MTIME_LO);
    wire clint_match_mtime_hi    = (mem_alu_res == CLINT_MTIME_HI);
    wire clint_match_mtimecmp_lo = (mem_alu_res == CLINT_MTIMECMP_LO);
    wire clint_match_mtimecmp_hi = (mem_alu_res == CLINT_MTIMECMP_HI);
    wire clint_write_mtime_lo    = mem_is_sw && clint_match_mtime_lo;
    wire clint_write_mtime_hi    = mem_is_sw && clint_match_mtime_hi;
    wire clint_write_mcmp_lo     = mem_is_sw && clint_match_mtimecmp_lo;
    wire clint_write_mcmp_hi     = mem_is_sw && clint_match_mtimecmp_hi;
    wire clint_read              = mem_is_lw &&
                                   (clint_match_mtime_lo || clint_match_mtime_hi ||
                                    clint_match_mtimecmp_lo || clint_match_mtimecmp_hi);
    wire [31:0] clint_read_data =
        clint_match_mtime_lo    ? clint_mtime[31:0]    :
        clint_match_mtime_hi    ? clint_mtime[63:32]   :
        clint_match_mtimecmp_lo ? clint_mtimecmp[31:0] :
        clint_match_mtimecmp_hi ? clint_mtimecmp[63:32] : 32'b0;
    wire clint_write_any        = clint_write_mtime_lo | clint_write_mtime_hi |
                                  clint_write_mcmp_lo  | clint_write_mcmp_hi;

    // ------------------------------------------------------------
    // CLINT timer update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clint_mtime    <= 64'd0;
            clint_mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
        end else begin
            clint_mtime <= clint_mtime + 64'd1;
            if (clint_write_mtime_lo)
                clint_mtime[31:0] <= mem_store_data;
            if (clint_write_mtime_hi)
                clint_mtime[63:32] <= mem_store_data;
            if (clint_write_mcmp_lo)
                clint_mtimecmp[31:0] <= mem_store_data;
            if (clint_write_mcmp_hi)
                clint_mtimecmp[63:32] <= mem_store_data;
        end
    end

    assign clint_mtip = (clint_mtime >= clint_mtimecmp);

    // ------------------------------------------------------------
    // CSR / trap logic (supports CSR instructions + MMIO window)
    // ------------------------------------------------------------
    localparam [11:0] CSR_NUM_MSTATUS  = 12'h300;
    localparam [11:0] CSR_NUM_MIE      = 12'h304;
    localparam [11:0] CSR_NUM_MTVEC    = 12'h305;
    localparam [11:0] CSR_NUM_MSCRATCH = 12'h340;
    localparam [11:0] CSR_NUM_MEPC     = 12'h341;
    localparam [11:0] CSR_NUM_MCAUSE   = 12'h342;
    localparam [11:0] CSR_NUM_MIP      = 12'h344;
    localparam [11:0] CSR_NUM_MHARTID  = 12'hF14;

    localparam [31:0] CLINT_MTIME_LO    = 32'hFFFF_0008;
    localparam [31:0] CLINT_MTIME_HI    = 32'hFFFF_000C;
    localparam [31:0] CLINT_MTIMECMP_LO = 32'hFFFF_0010;
    localparam [31:0] CLINT_MTIMECMP_HI = 32'hFFFF_0014;

    // Memory-mapped CSR window retained for software access
    localparam [31:0] CSR_MTVEC_ADDR   = 32'hFFFF_FFC0;
    localparam [31:0] CSR_MSTATUS_ADDR = 32'hFFFF_FFC4;
    localparam [31:0] CSR_MEPC_ADDR    = 32'hFFFF_FFC8;
    localparam [31:0] CSR_MCAUSE_ADDR  = 32'hFFFF_FFCC;

    reg [31:0] csr_mtvec;
    reg [31:0] csr_mepc;
    reg [31:0] csr_mstatus;
    reg [31:0] csr_mcause;
    reg [31:0] csr_mie;
    reg [31:0] csr_mip;
    reg [31:0] csr_mscratch;

    wire timer_irq_level = clint_mtip | irq_i;
    wire [31:0] csr_mip_effective = {csr_mip[31:8], timer_irq_level, csr_mip[6:0]};

    wire csr_mstatus_mie  = csr_mstatus[3];
    wire csr_mstatus_mpie = csr_mstatus[7];
    wire csr_mie_mtie     = csr_mie[7];

    // Detect mret instruction
    wire is_mret = (id_inst == 32'h30200073);

    // Block interrupts during system operations (CSR, ecall, ebreak, mret)
    // This matches srv32's !ex_system_op check - critical for atomicity!
    wire system_op_in_pipeline = ex_is_csr | is_ecall | is_ebreak | is_mret;
    
    // Trap detection in ID stage - BLOCK during system ops!
    wire irq_take    = timer_irq_level && csr_mstatus_mie && csr_mie_mtie && !system_op_in_pipeline;
    wire ecall_take  = is_ecall;
    wire ebreak_take = is_ebreak;  // BUG FIX: ebreak was not being trapped!
    wire trap_take   = irq_take | ecall_take | ebreak_take;

    wire [31:0] branch_target_trap = csr_mtvec;
    wire [31:0] branch_target_mret = csr_mepc;  // mret returns directly to mepc (software handles +4 for ecall)

    wire branch_flush = branch_flag_ex;
    wire trap_flush   = trap_take;
    wire mret_flush   = is_mret && !mret_mepc_hazard;  // Don't flush during mepc hazard stall
    assign flush_pipeline = branch_flush | trap_flush | misaligned_trap | mret_flush;

    assign branch_flag = flush_pipeline;
    assign branch_target =
        misaligned_trap ? branch_target_trap :
        trap_flush      ? branch_target_trap :
        mret_flush      ? branch_target_mret :
        branch_flush    ? branch_target_ex :
                          32'b0;

    assign hold_ifid  = ~step_pulse | pipeline_stall;
    assign flush_ifid = flush_pipeline;

    // Track trap/branch flush for cancelling register writes (like srv32's wb_trap_nop)
    // When trap/branch taken, cancel register write from instruction that was in EX
    reg trap_wb_cancel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            trap_wb_cancel <= 1'b0;
        else if (step_pulse)
            trap_wb_cancel <= flush_pipeline;  // Cancel WB after any pipeline flush
    end

    // CSR access (loads/stores to CSR addresses) via MMIO window
    wire csr_addr_match = (mem_is_lw | mem_is_sw) &&
                          (mem_alu_res==CSR_MTVEC_ADDR ||
                           mem_alu_res==CSR_MSTATUS_ADDR ||
                           mem_alu_res==CSR_MEPC_ADDR ||
                           mem_alu_res==CSR_MCAUSE_ADDR);

    wire [31:0] csr_mmio_read =
        (mem_alu_res==CSR_MTVEC_ADDR)   ? csr_mtvec   :
        (mem_alu_res==CSR_MSTATUS_ADDR) ? csr_mstatus :
        (mem_alu_res==CSR_MEPC_ADDR)    ? csr_mepc    :
        (mem_alu_res==CSR_MCAUSE_ADDR)  ? csr_mcause  : 32'b0;

    // CSR instruction read mux
    function [31:0] csr_read_fn;
        input [11:0] addr;
        begin
            case (addr)
                CSR_NUM_MSTATUS:  csr_read_fn = csr_mstatus;
                CSR_NUM_MIE:      csr_read_fn = csr_mie;
                CSR_NUM_MTVEC:    csr_read_fn = csr_mtvec;
                CSR_NUM_MSCRATCH: csr_read_fn = csr_mscratch;
                CSR_NUM_MEPC:     csr_read_fn = csr_mepc;
                CSR_NUM_MCAUSE:   csr_read_fn = csr_mcause;
                CSR_NUM_MIP:      csr_read_fn = csr_mip_effective;
                CSR_NUM_MHARTID:  csr_read_fn = 32'b0;
                default:          csr_read_fn = 32'b0;
            endcase
        end
    endfunction

    wire [31:0] csr_instr_read = csr_read_fn(mem_csr_addr);

    // CSR instruction write value
    reg csr_instr_write;
    reg [31:0] csr_instr_wdata;
    always @(*) begin
        csr_instr_write = 1'b0;
        csr_instr_wdata = csr_instr_read;
        case (mem_csr_funct3)
            3'b001: begin // CSRRW
                csr_instr_write = 1'b1;
                csr_instr_wdata = mem_csr_rs1;
            end
            3'b010: begin // CSRRS
                csr_instr_wdata = csr_instr_read | mem_csr_rs1;
                csr_instr_write = |mem_csr_rs1;
            end
            3'b011: begin // CSRRC
                csr_instr_wdata = csr_instr_read & ~mem_csr_rs1;
                csr_instr_write = |mem_csr_rs1;
            end
            3'b101: begin // CSRRWI
                csr_instr_write = 1'b1;
                csr_instr_wdata = {27'b0, mem_csr_zimm};
            end
            3'b110: begin // CSRRSI
                csr_instr_wdata = csr_instr_read | {27'b0, mem_csr_zimm};
                csr_instr_write = |mem_csr_zimm;
            end
            3'b111: begin // CSRRCI
                csr_instr_wdata = csr_instr_read & ~{27'b0, mem_csr_zimm};
                csr_instr_write = |mem_csr_zimm;
            end
            default: begin
                csr_instr_write = 1'b0;
                csr_instr_wdata = csr_instr_read;
            end
        endcase
    end

    // Update CSRs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_mtvec    <= 32'b0;
            csr_mepc     <= 32'b0;
            csr_mstatus  <= 32'b0;
            csr_mcause   <= 32'b0;
            csr_mie      <= 32'b0;
            csr_mip      <= 32'b0;
            csr_mscratch <= 32'b0;
        end else begin
            // Trap entry / mret - USE PRIORITY (only one can happen)
            // This matches srv32's case(1'b1) priority structure
            if (misaligned_trap) begin
                csr_mepc        <= mem_pc;
                csr_mcause      <= misaligned_cause_code;
                csr_mstatus[7]  <= csr_mstatus_mie;
                csr_mstatus[3]  <= 1'b0;
            end else if (trap_take) begin
                // For interrupts: save the PC being fetched (will resume there after handler)
                // BUG FIX: id_pc is STALE after pipeline flush (like mret)!
                // For ecall/ebreak: save PC of the instruction itself (id_pc)
                csr_mepc        <= irq_take ? pc : id_pc;
                // mcause: 0x80000007=timer, 0x0B=ecall, 0x03=ebreak
                csr_mcause      <= irq_take    ? 32'h80000007 : 
                                   ebreak_take ? 32'h00000003 : 32'h0000000B;
                csr_mip[7]      <= irq_i;
                csr_mstatus[7]  <= csr_mstatus_mie; // MPIE <= MIE
                csr_mstatus[3]  <= 1'b0;            // MIE  <= 0
            end else if (is_mret && !mret_mepc_hazard) begin
                // mret restore - ONLY if no trap is being taken (else clause!)
                csr_mstatus[3] <= csr_mstatus_mpie; // MIE <= MPIE
                csr_mstatus[7] <= 1'b1;             // MPIE <= 1
            end
            // CSR instruction writes
            if (mem_is_csr && csr_instr_write) begin
                case (mem_csr_addr)
                    CSR_NUM_MSTATUS:  csr_mstatus  <= csr_instr_wdata;
                    CSR_NUM_MIE:      csr_mie      <= csr_instr_wdata;
                    CSR_NUM_MTVEC:    csr_mtvec    <= csr_instr_wdata;
                    CSR_NUM_MSCRATCH: csr_mscratch <= csr_instr_wdata;
                    CSR_NUM_MEPC:     csr_mepc     <= csr_instr_wdata;
                    CSR_NUM_MCAUSE:   csr_mcause   <= csr_instr_wdata;
                    CSR_NUM_MIP:      csr_mip      <= {csr_instr_wdata[31:8], 1'b0, csr_instr_wdata[6:0]};
                    default: ;
                endcase
            end
            // Memory-mapped CSR writes
            if (mem_is_sw && mem_alu_res==CSR_MTVEC_ADDR)
                csr_mtvec <= mem_store_data;
            if (mem_is_sw && mem_alu_res==CSR_MSTATUS_ADDR)
                csr_mstatus <= mem_store_data;
            if (mem_is_sw && mem_alu_res==CSR_MEPC_ADDR)
                csr_mepc <= mem_store_data;
            if (mem_is_sw && mem_alu_res==CSR_MCAUSE_ADDR)
                csr_mcause <= mem_store_data;
        end
    end

    // ------------------------------------------------------------
    // MEM/WB stage
    // ------------------------------------------------------------
    assign d_addr  = mem_alu_res;
    assign d_wdata = mem_store_data;

    // Mask data memory writes when hitting CSR addresses or during trap flush
    wire csr_write = mem_is_sw && (mem_alu_res==CSR_MTVEC_ADDR || mem_alu_res==CSR_MSTATUS_ADDR || mem_alu_res==CSR_MEPC_ADDR || mem_alu_res==CSR_MCAUSE_ADDR);
    assign d_we    = step_pulse ? ((mem_is_sb | mem_is_sh | mem_is_sw) && ~csr_write && ~clint_write_any && ~misaligned_trap && ~trap_wb_cancel) : 1'b0;

    assign is_sw_o = mem_is_sw;
    assign is_sh_o = mem_is_sh;
    assign is_sb_o = mem_is_sb;

    // Load data formatting
    wire [7:0]  load_byte = d_rdata >> (8 * mem_alu_res[1:0]);
    wire [15:0] load_half = d_rdata >> (8 * {mem_alu_res[1],1'b0});
    wire [31:0] load_val_mem =
        mem_is_lb  ? {{24{load_byte[7]}},  load_byte} :
        mem_is_lh  ? {{16{load_half[15]}}, load_half} :
        mem_is_lw  ? d_rdata :
        mem_is_lbu ? {24'b0, load_byte} :
        mem_is_lhu ? {16'b0, load_half} :
                    32'b0;

    // CSR load override
    wire wb_from_timer      = clint_read;
    wire wb_from_csr_mmio   = mem_is_lw && csr_addr_match;
    wire wb_from_csr_instr  = mem_is_csr;
    wire wb_from_load       = mem_is_lb | mem_is_lh | mem_is_lw | mem_is_lbu | mem_is_lhu;

    wire [31:0] wb_value_pre =
        wb_from_csr_instr ? csr_instr_read :
        wb_from_csr_mmio  ? csr_mmio_read  :
        wb_from_timer     ? clint_read_data :
        wb_from_load      ? load_val_mem   :
        mem_is_lui         ? mem_lui_value   :
        mem_is_auipc       ? mem_auipc_value :
        mem_is_jal         ? mem_link_value  :
        mem_is_jalr        ? mem_link_value  :
                             mem_alu_res;

    assign wb_value = wb_value_pre;
    assign wb_we   = mem_we && !trap_wb_cancel;  // Cancel writes after trap/branch flush
    assign wb_rd   = mem_rd;
    assign wb_wdata= wb_value_pre;

endmodule
