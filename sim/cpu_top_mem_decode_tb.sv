`timescale 1ns / 1ps

module cpu_top_mem_decode_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n;
    reg btn0;
    reg [1:0] sw;
    reg uart_rx;
    wire [3:0] led;
    wire uart_tx;
    reg passed;
    reg ram_store_seen;
    reg clint_load_seen;
    reg unmapped_store_seen;
    reg unmapped_blocked;
    reg [31:0] prev_pc_display;
    integer pc_cycles;

    localparam [31:0] RAM_BASE      = 32'h0000_0000;
    localparam [31:0] RAM_END       = (16384 * 4) - 1;
    localparam [31:0] CLINT_BASE    = 32'hFFFF_0000;
    localparam [31:0] CLINT_END     = 32'hFFFF_001F;
    localparam [31:0] UNMAPPED_BASE = 32'h8000_0000;

    cpu_top dut_top (
        .clk100(clk),
        .rst_n(rst_n),
        .btn0(btn0),
        .sw(sw),
        .led(led),
        .uart_tx(uart_tx),
        .uart_rx(uart_rx)
    );

    task init_mem();
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1)
                dut_top.data_mem[i] = 32'h0;
        end
    endtask

    task load_program();
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1)
                dut_top.instr_mem[i] = 32'h00000013;
            dut_top.instr_mem[0] = 32'h01100093; // addi x1,x0,0x11
            dut_top.instr_mem[1] = 32'h00102023; // sw x1,0(x0)
            dut_top.instr_mem[2] = 32'hffff0137; // lui x2,0xffff0
            dut_top.instr_mem[3] = 32'h00012183; // lw x3,0(x2) -> CLINT load
            dut_top.instr_mem[4] = 32'h80000237; // lui x4,0x80000
            dut_top.instr_mem[5] = 32'h0011a023; // sw x1,0(x4) -> unmapped
        end
    endtask

    task run_cycles(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        if (dut_top.u_cpu.mem_is_sw) begin
            if (dut_top.u_cpu.mem_alu_res >= RAM_BASE && dut_top.u_cpu.mem_alu_res <= RAM_END)
                ram_store_seen <= 1;
            else if (dut_top.u_cpu.mem_alu_res >= UNMAPPED_BASE)
                begin
                    unmapped_store_seen <= 1;
                    if (dut_top.u_cpu.d_we == 1'b0)
                        unmapped_blocked <= 1;
                end
        end
        if (dut_top.u_cpu.mem_is_lw &&
            dut_top.u_cpu.mem_alu_res >= CLINT_BASE &&
            dut_top.u_cpu.mem_alu_res <= CLINT_END)
            clint_load_seen <= 1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pc_cycles <= 0;
            prev_pc_display <= 32'h0;
        end else if (pc_cycles < 8) begin
            if (pc_cycles > 0) begin
                if (dut_top.u_cpu.pc_o - prev_pc_display != 32'd4)
                    $display("cpu_top PC delta mismatch: prev=%h curr=%h diff=%h",
                             prev_pc_display, dut_top.u_cpu.pc_o,
                             dut_top.u_cpu.pc_o - prev_pc_display);
            end
            $display("cpu_top bringup cycle %0d pc=%h", pc_cycles, dut_top.u_cpu.pc_o);
            prev_pc_display <= dut_top.u_cpu.pc_o;
            pc_cycles <= pc_cycles + 1;
        end
    end

    initial begin
        btn0 = 0;
        sw = 2'b00;
        uart_rx = 1'b1;
        ram_store_seen = 0;
        clint_load_seen = 0;
        unmapped_store_seen = 0;
        unmapped_blocked = 0;
        init_mem();
        load_program();
        rst_n = 0;
        #20;
        rst_n = 1;
        run_cycles(400);
        passed = ram_store_seen &&
                 clint_load_seen &&
                 unmapped_store_seen &&
                 unmapped_blocked &&
                 (dut_top.data_mem[0] == 32'h11);
        $display("memory decode (RAM/CLINT/unmapped): %s", passed ? "PASS" : "FAIL");
        $finish;
    end
endmodule
