`timescale 1ns / 1ps

module cpu_core_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    wire [31:0] pc;
    wire [31:0] d_addr;
    wire [31:0] d_wdata;
    reg  [31:0] d_rdata_reg;
    wire [31:0] d_rdata = d_rdata_reg;
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


    always @(posedge clk) begin
        if (d_we && d_addr[31:16] == 16'h0000) begin
            reg [31:0] word = data_mem[d_addr[9:2]];
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
        if (d_addr[31:16] == 16'h0000)
            d_rdata_reg <= data_mem[d_addr[9:2]];
        else
            d_rdata_reg <= 32'h0;
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
        begin
            init_mem();
            instr_mem[0] = 32'h00300093; // addi x1,x0,3
            instr_mem[1] = 32'h00008133; // add x2,x1,x0
            instr_mem[2] = 32'h002101b3; // add x3,x2,x2
            instr_mem[3] = 32'h00302623; // sw x3,12(x0)
            instr_mem[4] = 32'h00208663; // beq x2,x1,12
            instr_mem[5] = 32'h00002223; // sw x0,16(x0)
            instr_mem[6] = 32'h00202a23; // sw x2,20(x0)
            reset_cpu();
            run_cycles(200);
            passed = check_mem(3, 6) && check_mem(4, 0) && check_mem(5, 3);
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
            instr_mem[4] = 32'h00102023; // sw x1,4(x0)
            instr_mem[8] = 32'h00200313; // addi x6,x0,2
            instr_mem[9] = 32'h00602023; // sw x6,0(x0)
            instr_mem[10] = 32'h30200073; // mret
            reset_cpu();
            run_cycles(300);
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
            instr_mem[3] = 32'h00303823; // sw x3,24(x0)
            reset_cpu();
            run_cycles(200);
            passed = check_mem(6, 171);
            $display("CSR hazard: %s", passed ? "PASS" : "FAIL");
        end
    endtask

    initial begin
        init_mem();
        reset_cpu();
        run_bringup();
        run_load_use();
        run_forward_branch();
        run_trap_mret();
        run_misaligned();
        run_csr_hazard();
        $display("CPU core tests completed");
        $finish;
    end
endmodule
