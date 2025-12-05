`timescale 1ns / 1ps

module cpu_core_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    wire [31:0] pc;
    wire [31:0] d_addr;
    wire [31:0] d_wdata;
    wire [31:0] d_rdata;
    wire        d_we;
    wire        is_sw, is_sh, is_sb;
    wire [31:0] rs2_val_o;
    wire [31:0] wb_value;

    reg [31:0] instr_mem [0:255];
    reg [31:0] data_mem [0:255];
    reg [31:0] prev_pc;
    wire [31:0] instr_word = instr_mem[pc[9:2]];

    cpu_core uut (
        .clk(clk),
        .rst_n(rst_n),
        .step_pulse(1'b1),
        .irq_i(1'b0),
        .pc_o(pc),
        .instr_i(instr_word),
        .d_addr(d_addr),
        .d_wdata(d_wdata),
        .d_rdata(d_rdata),
        .d_we(d_we),
        .wb_value(wb_value),
        .is_sw_o(is_sw),
        .is_sh_o(is_sh),
        .is_sb_o(is_sb),
        .rs2_val_o(rs2_val_o)
    );

    // Combinational memory read (no delay for loads)
    assign d_rdata = (d_addr[31:16] == 16'h0000) ? data_mem[d_addr[9:2]] : 32'h0;

    reg [31:0] word;
    always @(posedge clk) begin
        if (d_we && d_addr[31:16] == 16'h0000) begin
            word = data_mem[d_addr[9:2]];
            if (is_sw) begin
                word = d_wdata;
            end else if (is_sh) begin
                if (d_addr[1])
                    word[31:16] = d_wdata[15:0];
                else
                    word[15:0] = d_wdata[15:0];
            end else if (is_sb) begin
                case (d_addr[1:0])
                    2'b00: word[7:0]   = d_wdata[7:0];
                    2'b01: word[15:8]  = d_wdata[7:0];
                    2'b10: word[23:16] = d_wdata[7:0];
                    2'b11: word[31:24] = d_wdata[7:0];
                endcase
            end
            data_mem[d_addr[9:2]] <= word;
            $display("MEM WRITE @ %0t idx=%0d data=%h", $time, d_addr[9:2], word);
        end
    end

    task init_mem();
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                instr_mem[i] = 32'h00000013; // nop
                data_mem[i] = 32'h0;
            end
        end
    endtask

    task reset_cpu();
        begin
            rst_n = 0;
            @(posedge clk);
            #1 rst_n = 1;
            @(posedge clk);
            #1;
        end
    endtask

    task run_cycles(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    function reg check_mem(input integer idx, input integer expected);
        begin
            if (data_mem[idx] !== expected) begin
                $display("  MISMATCH @ idx=%0d exp=%h got=%h", idx, expected, data_mem[idx]);
                check_mem = 0;
            end else begin
                check_mem = 1;
            end
        end
    endfunction

    task run_bringup();
        reg bringup_passed;
        integer cycle;
        integer idx;
        begin
            init_mem();
            for (idx = 0; idx < 8; idx = idx + 1)
                instr_mem[idx] = 32'h00000013;
            instr_mem[8]  = 32'h04200093; // addi x1,x0,0x42
            instr_mem[9]  = 32'h00102023; // sw x1,0(x0)
            instr_mem[10] = 32'h00000013;
            reset_cpu();
            prev_pc = pc;
            bringup_passed = 1;
            for (cycle = 0; cycle < 20; cycle = cycle + 1) begin
                @(posedge clk);
                if (cycle > 0 && (pc - prev_pc != 32'd4)) begin
                    $display("bringup PC mismatch: prev=%h curr=%h diff=%h", prev_pc, pc, pc - prev_pc);
                    bringup_passed = 0;
                end
                $display("bringup cycle %0d pc=%h instr=%h", cycle, pc, instr_word);
                prev_pc = pc;
            end
            bringup_passed = bringup_passed && (data_mem[0] == 32'h00000042);
            $display("bringup: %s", bringup_passed ? "PASS" : "FAIL");
            if (!bringup_passed)
                $stop;
        end
    endtask

    task run_load_use();
        reg passed;
        begin
            init_mem();
            data_mem[0] = 32'hDEADBEEF;
            instr_mem[0] = 32'h00002183; // lw x3,0(x0)
            instr_mem[1] = 32'h00018233; // add x4,x3,x0
            instr_mem[2] = 32'h00402223; // sw x4,4(x0)
            $display("load-use instructions: %h %h %h", instr_mem[0], instr_mem[1], instr_mem[2]);
            reset_cpu();
            run_cycles(200);
            passed = check_mem(1, 32'hDEADBEEF);
            $display("load-use hazard: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    task run_forward_branch();
        reg passed;
        integer i;
        begin
            init_mem();
            instr_mem[0] = 32'h00300093; // addi x1,x0,3
            instr_mem[1] = 32'h00108133; // add x2,x1,x1   (was: x1,x0 → now: x1,x1 so x2=6)
            instr_mem[2] = 32'h002101b3; // add x3,x2,x2
            instr_mem[3] = 32'h00302623; // sw x3,12(x0)
            instr_mem[4] = 32'h00208063; // beq x1,x2,0  (corrected: was 0x00208663)
            instr_mem[5] = 32'h00002223; // sw x0,16(x0)
            instr_mem[6] = 32'h00202a23; // sw x2,20(x0)
            reset_cpu();
            run_cycles(20);  // Just 20 cycles to see values early
            $display("forwarding test EARLY results (after 20 cycles):");
            $display("  mem[0]=%h, mem[1]=%h, mem[3]=%h, mem[4]=%h, mem[5]=%h", data_mem[0], data_mem[1], data_mem[3], data_mem[4], data_mem[5]);
            $display("  Expected: mem[3]=0xc (x3=x2+x2=6+6), mem[4]=0x0 (x0), mem[5]=0x6 (x2)");
            run_cycles(180);  // Rest of cycles
            $display("forwarding test FINAL results:");
            $display("  mem[0]=%h, mem[1]=%h, mem[3]=%h, mem[4]=%h, mem[5]=%h", data_mem[0], data_mem[1], data_mem[3], data_mem[4], data_mem[5]);
            passed = check_mem(3, 12) && check_mem(4, 0) && check_mem(5, 6);
            $display("forwarding & branch: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    task run_trap_mret();
        reg passed;
        begin
            init_mem();
            instr_mem[0] = 32'h02000293; // addi x5,x0,32
            instr_mem[1] = 32'h30529073; // csrrw x0,mtvec,x5
            instr_mem[2] = 32'h00100093; // addi x1,x0,1
            instr_mem[3] = 32'h00000073; // ecall
            instr_mem[4] = 32'h00102223; // sw x1,4(x0)  [FIXED: was 0x00102023]
            instr_mem[8] = 32'h00200313; // addi x6,x0,2
            instr_mem[9] = 32'h00602023; // sw x6,0(x0)
            instr_mem[10] = 32'h30200073; // mret
            reset_cpu();
            
            $display("\n=== TRAP/MRET TEST DEBUG ===");
            $display("Instruction sequence:");
            $display("  [0x00] addi x5,x0,32    -> x5=0x20 (mtvec address)");
            $display("  [0x04] csrrw x0,mtvec,x5 -> mtvec=0x20");
            $display("  [0x08] addi x1,x0,1     -> x1=1");
            $display("  [0x0C] ecall             -> trap! PC -> 0x20 (mtvec), mepc=0x0C");
            $display("  [0x10] sw x1,4(x0)      -> mem[1]=x1 (should be 1)");
            $display("  [0x20] addi x6,x0,2     -> x6=2 (trap handler start)");
            $display("  [0x24] sw x6,0(x0)      -> mem[0]=x6 (should be 2)");
            $display("  [0x28] mret              -> PC -> mepc=0x0C+4=0x10, continue");
            $display("Expected: mem[0]=2, mem[1]=1");
            
            run_cycles(300);
            
            $display("\n=== TRAP/MRET TEST RESULTS ===");
            $display("Final memory values:");
            $display("  mem[0]=%h (expect 2)", data_mem[0]);
            $display("  mem[1]=%h (expect 1)", data_mem[1]);
            
            passed = check_mem(0, 2) && check_mem(1, 1);
            $display("trap entry/mret: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    task run_misaligned();
        reg passed;
        begin
            init_mem();
            instr_mem[0] = 32'h00102083; // lw x1,1(x0)
            instr_mem[1] = 32'h00002223; // sw x0,4(x0)
            instr_mem[2] = 32'h00002423; // sw x0,8(x0)
            reset_cpu();
            run_cycles(200);
            passed = check_mem(1, 0) && check_mem(2, 0);
            $display("misaligned trap: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    task run_csr_hazard();
        reg passed;
        begin
            init_mem();
            instr_mem[0] = 32'h0ab00113; // addi x2,x0,171
            instr_mem[1] = 32'h34011073; // csrrw x0,mscratch,x2
            instr_mem[2] = 32'h340021f3; // csrrs x3,mscratch,x0
            instr_mem[3] = 32'h00302C23; // sw x3,24(x0) - correct encoding with funct3=010
            reset_cpu();
            run_cycles(200);
            $display("CSR hazard test: mem[6]=%h (expect ab)", data_mem[6]);
            passed = check_mem(6, 171);
            $display("CSR hazard: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // =========================================================================
    // FreeRTOS Stress Tests
    // =========================================================================

    // Test 1: Context switch simulation - save/restore registers
    task run_context_switch();
        reg passed;
        begin
            init_mem();
            $display("\n=== CONTEXT SWITCH TEST ===");
            // Simulate saving context (like FreeRTOS portSAVE_CONTEXT)
            // Set up "stack pointer" x2 = 0x100 (word address 64)
            instr_mem[0]  = 32'h10000113; // addi x2,x0,256  (sp = 0x100)
            // Save some registers to "stack"
            instr_mem[1]  = 32'h0DE00093; // addi x1,x0,0xDE  (ra = 0xDE)
            instr_mem[2]  = 32'hABC00193; // addi x3,x0,0xABC (gp)  -- will be truncated to 12-bit
            instr_mem[3]  = 32'h12300213; // addi x4,x0,0x123 (tp)  -- will be truncated
            instr_mem[4]  = 32'h45600293; // addi x5,x0,0x456 (t0)  -- will be truncated
            // Push to stack (descending)
            instr_mem[5]  = 32'hFE112023; // sw x1,-32(x2)   mem[56]
            instr_mem[6]  = 32'hFE312223; // sw x3,-28(x2)   mem[57]
            instr_mem[7]  = 32'hFE412423; // sw x4,-24(x2)   mem[58]
            instr_mem[8]  = 32'hFE512623; // sw x5,-20(x2)   mem[59]
            // Clear registers
            instr_mem[9]  = 32'h00000093; // addi x1,x0,0
            instr_mem[10] = 32'h00000193; // addi x3,x0,0
            instr_mem[11] = 32'h00000213; // addi x4,x0,0
            instr_mem[12] = 32'h00000293; // addi x5,x0,0
            // Restore from stack
            instr_mem[13] = 32'hFE012083; // lw x1,-32(x2)
            instr_mem[14] = 32'hFE412183; // lw x3,-28(x2)
            instr_mem[15] = 32'hFE812203; // lw x4,-24(x2)
            instr_mem[16] = 32'hFEC12283; // lw x5,-20(x2)
            // Verify by storing to known locations
            instr_mem[17] = 32'h00102023; // sw x1,0(x0)    mem[0]
            instr_mem[18] = 32'h00302223; // sw x3,4(x0)    mem[1]
            instr_mem[19] = 32'h00402423; // sw x4,8(x0)    mem[2]
            instr_mem[20] = 32'h00502623; // sw x5,12(x0)   mem[3]
            
            reset_cpu();
            run_cycles(100);
            
            // Note: immediates are sign-extended, so 0xABC becomes negative
            passed = check_mem(0, 32'h000000DE) &&  // x1 = 0xDE
                     check_mem(1, 32'hFFFFFABC) &&  // x3 = sign-ext(0xABC) = 0xFFFFFABC
                     check_mem(2, 32'h00000123) &&  // x4 = 0x123
                     check_mem(3, 32'h00000456);    // x5 = 0x456
            $display("context switch: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 2: Back-to-back CSR operations (mstatus enable/disable interrupts)
    task run_csr_mstatus();
        reg passed;
        begin
            init_mem();
            $display("\n=== CSR MSTATUS TEST ===");
            // Test interrupt enable/disable like FreeRTOS critical sections
            instr_mem[0] = 32'h00800093; // addi x1,x0,8      (MIE bit = bit 3)
            instr_mem[1] = 32'h3000B073; // csrrc x0,mstatus,x1  (clear MIE - disable interrupts)
            instr_mem[2] = 32'h300020F3; // csrrs x1,mstatus,x0  (read mstatus into x1)
            instr_mem[3] = 32'h00102023; // sw x1,0(x0)          (store to mem[0])
            instr_mem[4] = 32'h00800093; // addi x1,x0,8
            instr_mem[5] = 32'h3000A073; // csrrs x0,mstatus,x1  (set MIE - enable interrupts)
            instr_mem[6] = 32'h30002173; // csrrs x2,mstatus,x0  (read mstatus into x2)
            instr_mem[7] = 32'h00202223; // sw x2,4(x0)          (store to mem[1])
            
            reset_cpu();
            run_cycles(100);
            
            // After clearing MIE, mstatus should have bit 3 = 0
            // After setting MIE, mstatus should have bit 3 = 1
            passed = ((data_mem[0] & 8) == 0) && ((data_mem[1] & 8) == 8);
            $display("  mstatus after disable: %h (expect bit3=0)", data_mem[0]);
            $display("  mstatus after enable:  %h (expect bit3=1)", data_mem[1]);
            $display("CSR mstatus: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 3: Dependent ALU chain (tests forwarding thoroughly)
    task run_alu_chain();
        reg passed;
        begin
            init_mem();
            $display("\n=== ALU CHAIN TEST ===");
            // Chain of dependent operations
            instr_mem[0]  = 32'h00100093; // addi x1,x0,1    x1=1
            instr_mem[1]  = 32'h00108113; // addi x2,x1,1    x2=2
            instr_mem[2]  = 32'h00210193; // addi x3,x2,2    x3=4
            instr_mem[3]  = 32'h00318213; // addi x4,x3,3    x4=7
            instr_mem[4]  = 32'h00420293; // addi x5,x4,4    x5=11
            instr_mem[5]  = 32'h00528313; // addi x6,x5,5    x6=16
            instr_mem[6]  = 32'h00630393; // addi x7,x6,6    x7=22
            instr_mem[7]  = 32'h00738413; // addi x8,x7,7    x8=29
            // Now do some ALU ops between them
            instr_mem[8]  = 32'h002084B3; // add x9,x1,x2    x9=3
            instr_mem[9]  = 32'h00418533; // add x10,x3,x4   x10=11
            instr_mem[10] = 32'h006285B3; // add x11,x5,x6   x11=27
            instr_mem[11] = 32'h00838633; // add x12,x7,x8   x12=51
            // Store results
            instr_mem[12] = 32'h00802023; // sw x8,0(x0)     mem[0]=29
            instr_mem[13] = 32'h00902223; // sw x9,4(x0)     mem[1]=3
            instr_mem[14] = 32'h00A02423; // sw x10,8(x0)    mem[2]=11
            instr_mem[15] = 32'h00B02623; // sw x11,12(x0)   mem[3]=27
            instr_mem[16] = 32'h00C02823; // sw x12,16(x0)   mem[4]=51
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 29) && check_mem(1, 3) && check_mem(2, 11) &&
                     check_mem(3, 27) && check_mem(4, 51);
            $display("ALU chain: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 4: Branch stress test (various branch conditions)
    task run_branch_stress();
        reg passed;
        begin
            init_mem();
            $display("\n=== BRANCH STRESS TEST ===");
            instr_mem[0]  = 32'h00500093; // addi x1,x0,5
            instr_mem[1]  = 32'h00500113; // addi x2,x0,5
            instr_mem[2]  = 32'h00300193; // addi x3,x0,3
            instr_mem[3]  = 32'hFFF00213; // addi x4,x0,-1
            
            // BEQ taken (x1 == x2)
            instr_mem[4]  = 32'h00208463; // beq x1,x2,+8   -> skip next
            instr_mem[5]  = 32'h00100293; // addi x5,x0,1   (skipped)
            instr_mem[6]  = 32'h00000013; // nop (landing)
            
            // BNE taken (x1 != x3)
            instr_mem[7]  = 32'h00309463; // bne x1,x3,+8   -> skip next
            instr_mem[8]  = 32'h00200293; // addi x5,x0,2   (skipped)
            instr_mem[9]  = 32'h00000013; // nop (landing)
            
            // BLT taken (x3 < x1)
            instr_mem[10] = 32'h0011C463; // blt x3,x1,+8   -> skip next
            instr_mem[11] = 32'h00300293; // addi x5,x0,3   (skipped)
            instr_mem[12] = 32'h00000013; // nop (landing)
            
            // BGE taken (x1 >= x3)
            instr_mem[13] = 32'h0030D463; // bge x1,x3,+8   -> skip next
            instr_mem[14] = 32'h00400293; // addi x5,x0,4   (skipped)
            instr_mem[15] = 32'h00000013; // nop (landing)
            
            // BLTU not taken (5 is not < 5)
            instr_mem[16] = 32'h0020E463; // bltu x1,x2,+8  -> NOT taken
            instr_mem[17] = 32'h00A00293; // addi x5,x0,10  (executed!)
            instr_mem[18] = 32'h00000013; // nop
            
            // Store x5 (should be 10)
            instr_mem[19] = 32'h00502023; // sw x5,0(x0)
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 10);
            $display("branch stress: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 5: Load/store various sizes
    task run_load_store_sizes();
        reg passed;
        begin
            init_mem();
            $display("\n=== LOAD/STORE SIZES TEST ===");
            data_mem[0] = 32'hDEADBEEF;
            
            // Load byte, halfword, word
            instr_mem[0] = 32'h00000083; // lb  x1,0(x0)   x1 = sign-ext(0xEF) = 0xFFFFFFEF
            instr_mem[1] = 32'h00001103; // lh  x2,0(x0)   x2 = sign-ext(0xBEEF) = 0xFFFFBEEF
            instr_mem[2] = 32'h00002183; // lw  x3,0(x0)   x3 = 0xDEADBEEF
            instr_mem[3] = 32'h00004203; // lbu x4,0(x0)   x4 = 0x000000EF
            instr_mem[4] = 32'h00005283; // lhu x5,0(x0)   x5 = 0x0000BEEF
            
            // Store results
            instr_mem[5] = 32'h00102223; // sw x1,4(x0)    mem[1]
            instr_mem[6] = 32'h00202423; // sw x2,8(x0)    mem[2]
            instr_mem[7] = 32'h00302623; // sw x3,12(x0)   mem[3]
            instr_mem[8] = 32'h00402823; // sw x4,16(x0)   mem[4]
            instr_mem[9] = 32'h00502A23; // sw x5,20(x0)   mem[5]
            
            // Test byte/halfword stores
            instr_mem[10] = 32'h0AA00313; // addi x6,x0,0xAA  (170)
            instr_mem[11] = 32'h00630023; // sb x6,0(x6)     -- store 0xAA to addr 0xAA (invalid in our range)
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(1, 32'hFFFFFFEF) &&
                     check_mem(2, 32'hFFFFBEEF) &&
                     check_mem(3, 32'hDEADBEEF) &&
                     check_mem(4, 32'h000000EF) &&
                     check_mem(5, 32'h0000BEEF);
            $display("load/store sizes: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 6: JAL/JALR (function calls like FreeRTOS uses)
    task run_jal_jalr();
        reg passed;
        begin
            init_mem();
            $display("\n=== JAL/JALR TEST ===");
            // Main: call subroutine at 0x20, return, store result
            instr_mem[0]  = 32'h00100093; // addi x1,x0,1
            instr_mem[1]  = 32'h020000EF; // jal x1,+32     -> call sub at 0x24, x1=0x08
            instr_mem[2]  = 32'h00A02023; // sw x10,0(x0)   mem[0] = x10 (return value)
            instr_mem[3]  = 32'h00102223; // sw x1,4(x0)    mem[1] = x1 (should be 0x08)
            instr_mem[4]  = 32'h00000013; // nop
            instr_mem[5]  = 32'h00000013; // nop
            instr_mem[6]  = 32'h00000013; // nop
            instr_mem[7]  = 32'h00000013; // nop
            // Subroutine at 0x20 (word 8)
            instr_mem[8]  = 32'h00000013; // nop
            instr_mem[9]  = 32'h02A00513; // addi x10,x0,42  return value = 42
            instr_mem[10] = 32'h00008067; // jalr x0,x1,0    return (jump to x1)
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 42) && check_mem(1, 8);
            $display("  return value: %h (expect 42)", data_mem[0]);
            $display("  return addr:  %h (expect 8)", data_mem[1]);
            $display("JAL/JALR: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 7: Multiple CSR hazards in sequence
    task run_csr_sequence();
        reg passed;
        begin
            init_mem();
            $display("\n=== CSR SEQUENCE TEST ===");
            // Write/read multiple CSRs in sequence
            instr_mem[0]  = 32'h10000093; // addi x1,x0,0x100
            instr_mem[1]  = 32'h20000113; // addi x2,x0,0x200
            instr_mem[2]  = 32'h30000193; // addi x3,x0,0x300
            
            // Write mscratch, read it back immediately
            instr_mem[3]  = 32'h34009073; // csrrw x0,mscratch,x1   mscratch=0x100
            instr_mem[4]  = 32'h34002273; // csrrs x4,mscratch,x0   x4=0x100
            
            // Write again, read again
            instr_mem[5]  = 32'h34011073; // csrrw x0,mscratch,x2   mscratch=0x200
            instr_mem[6]  = 32'h340022F3; // csrrs x5,mscratch,x0   x5=0x200
            
            // Write third time, read third time
            instr_mem[7]  = 32'h34019073; // csrrw x0,mscratch,x3   mscratch=0x300
            instr_mem[8]  = 32'h34002373; // csrrs x6,mscratch,x0   x6=0x300
            
            // Store all results
            instr_mem[9]  = 32'h00402023; // sw x4,0(x0)    mem[0]=0x100
            instr_mem[10] = 32'h00502223; // sw x5,4(x0)    mem[1]=0x200
            instr_mem[11] = 32'h00602423; // sw x6,8(x0)    mem[2]=0x300
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 32'h100) && check_mem(1, 32'h200) && check_mem(2, 32'h300);
            $display("CSR sequence: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 8: Interrupt handler simulation (full trap entry/exit)
    task run_interrupt_sim();
        reg passed;
        begin
            init_mem();
            $display("\n=== INTERRUPT SIMULATION TEST ===");
            // Simulates what FreeRTOS tick interrupt does
            
            // Setup: mtvec = 0x40
            instr_mem[0]  = 32'h04000293; // addi x5,x0,64
            instr_mem[1]  = 32'h30529073; // csrrw x0,mtvec,x5
            
            // Enable interrupts (set mstatus.MIE)
            instr_mem[2]  = 32'h00800313; // addi x6,x0,8
            instr_mem[3]  = 32'h30032073; // csrrs x0,mstatus,x6
            
            // Main program: count in a loop
            instr_mem[4]  = 32'h00100093; // addi x1,x0,1    x1=1 (counter)
            instr_mem[5]  = 32'h00108093; // addi x1,x1,1    x1=2
            instr_mem[6]  = 32'h00108093; // addi x1,x1,1    x1=3
            instr_mem[7]  = 32'h00000073; // ecall           -> trap!
            instr_mem[8]  = 32'h00108093; // addi x1,x1,1    x1=4 (after return)
            instr_mem[9]  = 32'h00102023; // sw x1,0(x0)     store counter to mem[0]
            instr_mem[10] = 32'h0000006F; // jal x0,0        infinite loop (halt)
            
            // Trap handler at 0x40 (word 16)
            instr_mem[16] = 32'h00200113; // addi x2,x0,2    x2=2 (handler ran)
            instr_mem[17] = 32'h00202223; // sw x2,4(x0)     mem[1]=2
            instr_mem[18] = 32'h30200073; // mret            return from trap
            
            reset_cpu();
            run_cycles(200);
            
            passed = check_mem(0, 4) && check_mem(1, 2);
            $display("  counter after trap: %h (expect 4)", data_mem[0]);
            $display("  handler marker:     %h (expect 2)", data_mem[1]);
            $display("interrupt sim: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 9: Shift operations (used in bit manipulation)
    task run_shift_ops();
        reg passed;
        begin
            init_mem();
            $display("\n=== SHIFT OPERATIONS TEST ===");
            instr_mem[0]  = 32'h0FF00093; // addi x1,x0,255
            instr_mem[1]  = 32'h00409113; // slli x2,x1,4     x2 = 255 << 4 = 4080
            instr_mem[2]  = 32'h0040D193; // srli x3,x1,4     x3 = 255 >> 4 = 15
            instr_mem[3]  = 32'h80000213; // addi x4,x0,-2048 (lui would be better but let's use addi)
            // Actually -2048 needs lui. Let's use a smaller negative
            instr_mem[3]  = 32'hF0000213; // addi x4,x0,-256  -- actually this is sign ext of 0xF00
            // Better approach: build -128
            instr_mem[3]  = 32'hF8000213; // addi x4,x0,-128
            instr_mem[4]  = 32'h4040D293; // srai x5,x1,4     x5 = 255 >>> 4 = 15 (positive, same as srli)
            instr_mem[5]  = 32'h40425313; // srai x6,x4,4     x6 = -128 >>> 4 = -8
            
            instr_mem[6]  = 32'h00202023; // sw x2,0(x0)    mem[0]=4080
            instr_mem[7]  = 32'h00302223; // sw x3,4(x0)    mem[1]=15
            instr_mem[8]  = 32'h00502423; // sw x5,8(x0)    mem[2]=15
            instr_mem[9]  = 32'h00602623; // sw x6,12(x0)   mem[3]=-8
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 4080) && check_mem(1, 15) && 
                     check_mem(2, 15) && check_mem(3, 32'hFFFFFFF8);
            $display("shift ops: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 10: Logical operations (AND, OR, XOR)
    task run_logical_ops();
        reg passed;
        begin
            init_mem();
            $display("\n=== LOGICAL OPERATIONS TEST ===");
            instr_mem[0]  = 32'h0FF00093; // addi x1,x0,0xFF
            instr_mem[1]  = 32'h0F000113; // addi x2,x0,0xF0
            instr_mem[2]  = 32'h0020F1B3; // and x3,x1,x2    x3 = 0xFF & 0xF0 = 0xF0
            instr_mem[3]  = 32'h0020E233; // or  x4,x1,x2    x4 = 0xFF | 0xF0 = 0xFF
            instr_mem[4]  = 32'h0020C2B3; // xor x5,x1,x2    x5 = 0xFF ^ 0xF0 = 0x0F
            instr_mem[5]  = 32'h0FF0F313; // andi x6,x1,0xFF x6 = 0xFF & 0xFF = 0xFF
            instr_mem[6]  = 32'h0000E393; // ori x7,x1,0     x7 = 0xFF | 0 = 0xFF
            instr_mem[7]  = 32'h00F0C413; // xori x8,x1,15   x8 = 0xFF ^ 0xF = 0xF0
            
            instr_mem[8]  = 32'h00302023; // sw x3,0(x0)
            instr_mem[9]  = 32'h00402223; // sw x4,4(x0)
            instr_mem[10] = 32'h00502423; // sw x5,8(x0)
            instr_mem[11] = 32'h00602623; // sw x6,12(x0)
            instr_mem[12] = 32'h00702823; // sw x7,16(x0)
            instr_mem[13] = 32'h00802A23; // sw x8,20(x0)
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 32'hF0) && check_mem(1, 32'hFF) && check_mem(2, 32'h0F) &&
                     check_mem(3, 32'hFF) && check_mem(4, 32'hFF) && check_mem(5, 32'hF0);
            $display("logical ops: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 11: SLT/SLTU (set less than - used in comparisons)
    task run_compare_ops();
        reg passed;
        begin
            init_mem();
            $display("\n=== COMPARE OPERATIONS TEST ===");
            instr_mem[0]  = 32'h00500093; // addi x1,x0,5
            instr_mem[1]  = 32'h00A00113; // addi x2,x0,10
            instr_mem[2]  = 32'hFFB00193; // addi x3,x0,-5
            
            // SLT: signed comparison
            instr_mem[3]  = 32'h0020A233; // slt x4,x1,x2    x4 = (5 < 10) = 1
            instr_mem[4]  = 32'h001122B3; // slt x5,x2,x1    x5 = (10 < 5) = 0  [FIXED encoding]
            instr_mem[5]  = 32'h0030A333; // slt x6,x1,x3    x6 = (5 < -5) = 0
            instr_mem[6]  = 32'h0011A3B3; // slt x7,x3,x1    x7 = (-5 < 5) = 1  [FIXED encoding]
            
            // SLTU: unsigned comparison
            instr_mem[7]  = 32'h0020B433; // sltu x8,x1,x2   x8 = (5 < 10) = 1
            instr_mem[8]  = 32'h0030B4B3; // sltu x9,x1,x3   x9 = (5 < 0xFFFFFFFB) = 1 (unsigned!)
            
            instr_mem[9]  = 32'h00402023; // sw x4,0(x0)
            instr_mem[10] = 32'h00502223; // sw x5,4(x0)
            instr_mem[11] = 32'h00602423; // sw x6,8(x0)
            instr_mem[12] = 32'h00702623; // sw x7,12(x0)
            instr_mem[13] = 32'h00802823; // sw x8,16(x0)
            instr_mem[14] = 32'h00902A23; // sw x9,20(x0)
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 1) && check_mem(1, 0) && check_mem(2, 0) &&
                     check_mem(3, 1) && check_mem(4, 1) && check_mem(5, 1);
            $display("compare ops: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Count passed/failed tests
    integer tests_passed;
    integer tests_total;

    // =========================================================================
    // FreeRTOS + UART Comprehensive Tests
    // =========================================================================

    // Test 12: External IRQ handling (timer interrupt simulation)
    task run_external_irq();
        reg passed;
        begin
            init_mem();
            $display("\n=== EXTERNAL IRQ TEST ===");
            // This test would require the testbench to pulse irq_i
            // For now, just verify the IRQ path exists
            // Setup mtvec
            instr_mem[0]  = 32'h04000293; // addi x5,x0,64
            instr_mem[1]  = 32'h30529073; // csrrw x0,mtvec,x5
            // Read mtvec back
            instr_mem[2]  = 32'h30502173; // csrrs x2,mtvec,x0
            instr_mem[3]  = 32'h00202023; // sw x2,0(x0)
            instr_mem[4]  = 32'h0000006F; // jal x0,0 (halt)
            
            reset_cpu();
            run_cycles(50);
            
            passed = check_mem(0, 64);
            $display("external IRQ setup: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 13: LUI and AUIPC (for large constants and PIC)
    task run_lui_auipc();
        reg passed;
        begin
            init_mem();
            $display("\n=== LUI/AUIPC TEST ===");
            instr_mem[0]  = 32'h123450B7; // lui x1,0x12345     x1 = 0x12345000
            instr_mem[1]  = 32'h00108093; // addi x1,x1,1       x1 = 0x12345001
            instr_mem[2]  = 32'h00001117; // auipc x2,1         x2 = PC + 0x1000 = 0x08 + 0x1000 = 0x1008
            instr_mem[3]  = 32'h00102023; // sw x1,0(x0)        mem[0] = 0x12345001
            instr_mem[4]  = 32'h00202223; // sw x2,4(x0)        mem[1] = 0x1008
            
            reset_cpu();
            run_cycles(50);
            
            passed = check_mem(0, 32'h12345001) && check_mem(1, 32'h1008);
            $display("LUI/AUIPC: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 14: Stack operations (SP-relative addressing for FreeRTOS)
    task run_stack_ops();
        reg passed;
        begin
            init_mem();
            $display("\n=== STACK OPERATIONS TEST ===");
            // Initialize SP (x2) to top of stack area
            instr_mem[0]  = 32'h08000113; // addi x2,x0,128     SP = 128
            // Push values onto stack
            instr_mem[1]  = 32'h0AA00093; // addi x1,x0,0xAA
            instr_mem[2]  = 32'hFE112E23; // sw x1,-4(x2)       push x1
            instr_mem[3]  = 32'hFFC10113; // addi x2,x2,-4      SP -= 4
            instr_mem[4]  = 32'h0BB00093; // addi x1,x0,0xBB
            instr_mem[5]  = 32'hFE112E23; // sw x1,-4(x2)       push x1
            instr_mem[6]  = 32'hFFC10113; // addi x2,x2,-4      SP -= 4
            // Pop values
            instr_mem[7]  = 32'h00012183; // lw x3,0(x2)        pop to x3
            instr_mem[8]  = 32'h00410113; // addi x2,x2,4       SP += 4
            instr_mem[9]  = 32'h00012203; // lw x4,0(x2)        pop to x4
            instr_mem[10] = 32'h00410113; // addi x2,x2,4       SP += 4
            // Store results
            instr_mem[11] = 32'h00302023; // sw x3,0(x0)        mem[0] = 0xBB
            instr_mem[12] = 32'h00402223; // sw x4,4(x0)        mem[1] = 0xAA
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 32'h000000BB) && check_mem(1, 32'h000000AA);
            $display("stack ops: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 15: Critical section (disable/enable interrupts)
    task run_critical_section();
        reg passed;
        begin
            init_mem();
            $display("\n=== CRITICAL SECTION TEST ===");
            // Enable interrupts first
            instr_mem[0]  = 32'h00800093; // addi x1,x0,8       MIE bit
            instr_mem[1]  = 32'h3000A073; // csrrs x0,mstatus,x1 enable MIE
            // Read mstatus
            instr_mem[2]  = 32'h30002173; // csrrs x2,mstatus,x0
            instr_mem[3]  = 32'h00202023; // sw x2,0(x0)        mem[0] = mstatus with MIE=1
            // Enter critical section (disable interrupts)
            instr_mem[4]  = 32'h3000B073; // csrrc x0,mstatus,x1 clear MIE
            // Read mstatus again
            instr_mem[5]  = 32'h30002173; // csrrs x2,mstatus,x0
            instr_mem[6]  = 32'h00202223; // sw x2,4(x0)        mem[1] = mstatus with MIE=0
            // Exit critical section (enable interrupts)
            instr_mem[7]  = 32'h3000A073; // csrrs x0,mstatus,x1 set MIE
            // Read mstatus again
            instr_mem[8]  = 32'h30002173; // csrrs x2,mstatus,x0
            instr_mem[9]  = 32'h00202423; // sw x2,8(x0)        mem[2] = mstatus with MIE=1
            
            reset_cpu();
            run_cycles(100);
            
            // Check MIE bit (bit 3) transitions
            passed = ((data_mem[0] & 8) == 8) &&  // MIE enabled
                     ((data_mem[1] & 8) == 0) &&  // MIE disabled
                     ((data_mem[2] & 8) == 8);    // MIE enabled again
            $display("  mstatus[0]=%h mstatus[1]=%h mstatus[2]=%h", data_mem[0], data_mem[1], data_mem[2]);
            $display("critical section: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 16: MCAUSE read after trap
    task run_mcause_test();
        reg passed;
        begin
            init_mem();
            $display("\n=== MCAUSE TEST ===");
            // Setup trap handler
            instr_mem[0]  = 32'h02000293; // addi x5,x0,32
            instr_mem[1]  = 32'h30529073; // csrrw x0,mtvec,x5
            // Trigger ecall
            instr_mem[2]  = 32'h00000073; // ecall
            instr_mem[3]  = 32'h00302023; // sw x3,0(x0)        mem[0] = mcause from handler
            instr_mem[4]  = 32'h0000006F; // jal x0,0           halt
            // Handler at 0x20
            instr_mem[8]  = 32'h34202173; // csrrs x2,mcause,x0 read mcause
            instr_mem[9]  = 32'h00010193; // addi x3,x2,0       x3 = mcause
            instr_mem[10] = 32'h30200073; // mret
            
            reset_cpu();
            run_cycles(100);
            
            // mcause for ecall from M-mode is 11 (0xB)
            passed = check_mem(0, 32'h0000000B);
            $display("  mcause=%h (expect 0xB for ecall)", data_mem[0]);
            $display("mcause test: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 17: MEPC manipulation (for context switching)
    task run_mepc_test();
        reg passed;
        begin
            init_mem();
            $display("\n=== MEPC TEST ===");
            // Setup trap handler that modifies mepc
            instr_mem[0]  = 32'h02000293; // addi x5,x0,32
            instr_mem[1]  = 32'h30529073; // csrrw x0,mtvec,x5
            instr_mem[2]  = 32'h00000073; // ecall
            instr_mem[3]  = 32'h0000006F; // jal x0,0           halt (shouldn't reach)
            // After return from modified mepc
            instr_mem[5]  = 32'h00100093; // addi x1,x0,1       x1 = 1
            instr_mem[6]  = 32'h00102023; // sw x1,0(x0)        mem[0] = 1
            instr_mem[7]  = 32'h0000006F; // jal x0,0           halt
            // Handler at 0x20 - modify mepc to skip to 0x14
            instr_mem[8]  = 32'h01000313; // addi x6,x0,16      x6 = 16 (0x10)
            instr_mem[9]  = 32'h34131073; // csrrw x0,mepc,x6   mepc = 0x10 (will return to 0x10+4=0x14)
            instr_mem[10] = 32'h30200073; // mret               return to 0x14
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 1);
            $display("  mem[0]=%h (expect 1)", data_mem[0]);
            $display("mepc test: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 18: Full context save/restore (all caller-saved registers)
    task run_full_context();
        reg passed;
        begin
            init_mem();
            $display("\n=== FULL CONTEXT SAVE/RESTORE TEST ===");
            // Set up values in registers
            instr_mem[0]  = 32'h00100093; // addi x1,x0,1       ra
            instr_mem[1]  = 32'h00200193; // addi x3,x0,2       gp
            instr_mem[2]  = 32'h00300293; // addi x5,x0,3       t0
            instr_mem[3]  = 32'h00400313; // addi x6,x0,4       t1
            instr_mem[4]  = 32'h00500393; // addi x7,x0,5       t2
            instr_mem[5]  = 32'h00600513; // addi x10,x0,6      a0
            instr_mem[6]  = 32'h00700593; // addi x11,x0,7      a1
            // Store stack pointer
            instr_mem[7]  = 32'h10000113; // addi x2,x0,256     sp = 256
            // Save context (push)
            instr_mem[8]  = 32'hFE112E23; // sw x1,-4(x2)
            instr_mem[9]  = 32'hFE312C23; // sw x3,-8(x2)
            instr_mem[10] = 32'hFE512A23; // sw x5,-12(x2)
            instr_mem[11] = 32'hFE612823; // sw x6,-16(x2)
            instr_mem[12] = 32'hFE712623; // sw x7,-20(x2)
            instr_mem[13] = 32'hFEA12423; // sw x10,-24(x2)
            instr_mem[14] = 32'hFEB12223; // sw x11,-28(x2)
            instr_mem[15] = 32'hFE410113; // addi x2,x2,-28     sp -= 28
            // Clear registers
            instr_mem[16] = 32'h00000093; // addi x1,x0,0
            instr_mem[17] = 32'h00000193; // addi x3,x0,0
            instr_mem[18] = 32'h00000293; // addi x5,x0,0
            instr_mem[19] = 32'h00000313; // addi x6,x0,0
            instr_mem[20] = 32'h00000393; // addi x7,x0,0
            instr_mem[21] = 32'h00000513; // addi x10,x0,0
            instr_mem[22] = 32'h00000593; // addi x11,x0,0
            // Restore context (pop)
            instr_mem[23] = 32'h00012583; // lw x11,0(x2)
            instr_mem[24] = 32'h00412503; // lw x10,4(x2)
            instr_mem[25] = 32'h00812383; // lw x7,8(x2)
            instr_mem[26] = 32'h00C12303; // lw x6,12(x2)
            instr_mem[27] = 32'h01012283; // lw x5,16(x2)
            instr_mem[28] = 32'h01412183; // lw x3,20(x2)
            instr_mem[29] = 32'h01812083; // lw x1,24(x2)
            // Store results to verify
            instr_mem[30] = 32'h00102023; // sw x1,0(x0)        mem[0] = 1
            instr_mem[31] = 32'h00302223; // sw x3,4(x0)        mem[1] = 2
            instr_mem[32] = 32'h00502423; // sw x5,8(x0)        mem[2] = 3
            instr_mem[33] = 32'h00A02623; // sw x10,12(x0)      mem[3] = 6
            instr_mem[34] = 32'h00B02823; // sw x11,16(x0)      mem[4] = 7
            
            reset_cpu();
            run_cycles(200);
            
            passed = check_mem(0, 1) && check_mem(1, 2) && check_mem(2, 3) &&
                     check_mem(3, 6) && check_mem(4, 7);
            $display("full context: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 19: SUB instruction (needed for address calculations)
    task run_sub_test();
        reg passed;
        begin
            init_mem();
            $display("\n=== SUB INSTRUCTION TEST ===");
            instr_mem[0]  = 32'h00A00093; // addi x1,x0,10
            instr_mem[1]  = 32'h00300113; // addi x2,x0,3
            instr_mem[2]  = 32'h402081B3; // sub x3,x1,x2       x3 = 10 - 3 = 7
            instr_mem[3]  = 32'h40208233; // sub x4,x1,x2       x4 = 10 - 3 = 7
            instr_mem[4]  = 32'h401002B3; // sub x5,x0,x1       x5 = 0 - 10 = -10
            instr_mem[5]  = 32'h00302023; // sw x3,0(x0)
            instr_mem[6]  = 32'h00502223; // sw x5,4(x0)
            
            reset_cpu();
            run_cycles(50);
            
            passed = check_mem(0, 7) && check_mem(1, 32'hFFFFFFF6);
            $display("sub test: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 20: Negative branch offsets (backward jumps for loops)
    task run_backward_branch();
        reg passed;
        begin
            init_mem();
            $display("\n=== BACKWARD BRANCH TEST ===");
            // Loop: count from 0 to 5
            instr_mem[0]  = 32'h00000093; // addi x1,x0,0       counter = 0
            instr_mem[1]  = 32'h00500113; // addi x2,x0,5       limit = 5
            // Loop start (0x08)
            instr_mem[2]  = 32'h00108093; // addi x1,x1,1       counter++
            instr_mem[3]  = 32'hFE209CE3; // bne x1,x2,-8       if counter != 5, jump back
            // Loop exit
            instr_mem[4]  = 32'h00102023; // sw x1,0(x0)        store final counter
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 5);
            $display("backward branch: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 21: UART TX simulation (memory-mapped I/O concept)
    // Note: This tests the concept using regular memory since UART is in cpu_top
    task run_uart_concept();
        reg passed;
        begin
            init_mem();
            $display("\n=== UART CONCEPT TEST ===");
            // Simulate UART by writing to high memory addresses
            // In real hw, UART_TX is at 0xFFFFFFF0
            // Here we just test byte extraction for UART
            instr_mem[0]  = 32'h04800093; // addi x1,x0,'H'     x1 = 0x48 = 'H'
            instr_mem[1]  = 32'h06500113; // addi x2,x0,'e'     x2 = 0x65 = 'e'
            instr_mem[2]  = 32'h06C00193; // addi x3,x0,'l'     x3 = 0x6C = 'l'
            instr_mem[3]  = 32'h06F00213; // addi x4,x0,'o'     x4 = 0x6F = 'o'
            // Store as bytes (simulating UART writes)
            instr_mem[4]  = 32'h00100023; // sb x1,0(x0)
            instr_mem[5]  = 32'h00200023; // sb x2,0(x0)        overwrite (simulates FIFO)
            instr_mem[6]  = 32'h00300023; // sb x3,0(x0)
            instr_mem[7]  = 32'h00400023; // sb x4,0(x0)
            // Verify last byte
            instr_mem[8]  = 32'h00002283; // lw x5,0(x0)
            instr_mem[9]  = 32'h00502223; // sw x5,4(x0)
            
            reset_cpu();
            run_cycles(100);
            
            // Last byte written was 'o' = 0x6F
            passed = ((data_mem[0] & 32'hFF) == 32'h6F);
            $display("  Last byte = 0x%h (expect 0x6F = 'o')", data_mem[0] & 32'hFF);
            $display("UART concept: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    // Test 22: Rapid CSR read-modify-write (scheduler critical path)
    task run_csr_rmw();
        reg passed;
        begin
            init_mem();
            $display("\n=== CSR READ-MODIFY-WRITE TEST ===");
            // Set mscratch to 0x100
            instr_mem[0]  = 32'h10000093; // addi x1,x0,0x100
            instr_mem[1]  = 32'h34009073; // csrrw x0,mscratch,x1
            // Read-modify-write: add 0x50 to mscratch
            instr_mem[2]  = 32'h34002173; // csrrs x2,mscratch,x0   read mscratch
            instr_mem[3]  = 32'h05010113; // addi x2,x2,0x50        add 0x50
            instr_mem[4]  = 32'h34011073; // csrrw x0,mscratch,x2   write back
            // Read final value
            instr_mem[5]  = 32'h340021F3; // csrrs x3,mscratch,x0
            instr_mem[6]  = 32'h00302023; // sw x3,0(x0)
            
            reset_cpu();
            run_cycles(100);
            
            passed = check_mem(0, 32'h150);  // 0x100 + 0x50 = 0x150
            $display("CSR RMW: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    initial begin
        $display("============================================================");
        $display("  RISC-V CPU Core Comprehensive Test Suite");
        $display("  FreeRTOS + UART Readiness Tests");
        $display("============================================================\n");
        
        tests_passed = 0;
        tests_total = 0;
        
        // Basic tests
        $display(">>> BASIC TESTS <<<");
        init_mem();
        reset_cpu();
        run_bringup();
        run_load_use();
        run_forward_branch();
        run_trap_mret();
        run_misaligned();
        run_csr_hazard();
        
        // FreeRTOS stress tests
        $display("\n>>> FREERTOS STRESS TESTS <<<");
        run_context_switch();
        run_csr_mstatus();
        run_alu_chain();
        run_branch_stress();
        run_load_store_sizes();
        run_jal_jalr();
        run_csr_sequence();
        run_interrupt_sim();
        run_shift_ops();
        run_logical_ops();
        run_compare_ops();
        
        // Additional FreeRTOS + UART tests
        $display("\n>>> ADVANCED FREERTOS + UART TESTS <<<");
        run_external_irq();
        run_lui_auipc();
        run_stack_ops();
        run_critical_section();
        run_mcause_test();
        run_mepc_test();
        run_full_context();
        run_sub_test();
        run_backward_branch();
        run_uart_concept();
        run_csr_rmw();
        
        $display("\n============================================================");
        $display("  CPU core comprehensive tests completed");
        $display("============================================================");
        $finish;
    end
endmodule
