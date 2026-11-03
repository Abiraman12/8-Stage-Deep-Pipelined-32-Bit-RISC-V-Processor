`timescale 1ns/1ps
// =============================================================================
// Self-checking testbench for riscv_8stage_top
//
// For every test program (tests/tN_*.hex) the testbench checks:
//   * all 32 registers and all 256 data-memory words against a golden model
//     (produced by tools/rvasm.py, an independent ISS written from the RISC-V spec)
//   * hand-calculated spot values (literals written below, independent of the golden files)
//   * retirement ORDER (PC of every retired instruction) and retired count
//   * performance counters: load-use stalls, redirects (taken branches/jumps) and total
//     cycles  (cycles = N + 7 + S + 4*T  for this 8-stage pipeline)
//   * no instruction after ECALL/EBREAK changes any state
//   * x0 stays zero, no stall+flush overlap, no illegal instruction, no X on the PC
// Run from the project root folder so that "tests/..." paths resolve.
// =============================================================================
module tb_riscv_8stage;

    localparam MAX_CYCLES = 3000;
    localparam NUM_TESTS  = 7;

    reg clk;
    reg reset;

    // ---------------- DUT connections ----------------
    wire [31:0] dbg_pc;
    wire [7:0]  dbg_valid;
    wire [31:0] dbg_instr_if2, dbg_instr_id, dbg_instr_rr, dbg_instr_ex;
    wire [31:0] dbg_instr_mem1, dbg_instr_mem2, dbg_instr_wb;
    wire [31:0] dbg_alu_result;
    wire        dbg_dmem_re, dbg_dmem_we;
    wire [31:0] dbg_dmem_addr, dbg_dmem_wdata;
    wire [1:0]  dbg_fwd_a, dbg_fwd_b;
    wire        dbg_load_use_stall, dbg_flush, dbg_redirect, dbg_halted, dbg_illegal_ex;
    wire        dbg_wb_we;
    wire [4:0]  dbg_wb_rd;
    wire [31:0] dbg_wb_data;
    wire        retire_valid;
    wire [31:0] retire_pc, retire_instr;
    wire        retire_halt;
    wire [31:0] cycle_count, retired_count, load_use_stall_count, redirect_count;
    wire        perf_done;

    riscv_8stage_top dut (
        .clk(clk), .reset(reset),
        .dbg_pc(dbg_pc), .dbg_valid(dbg_valid),
        .dbg_instr_if2(dbg_instr_if2), .dbg_instr_id(dbg_instr_id),
        .dbg_instr_rr(dbg_instr_rr), .dbg_instr_ex(dbg_instr_ex),
        .dbg_instr_mem1(dbg_instr_mem1), .dbg_instr_mem2(dbg_instr_mem2),
        .dbg_instr_wb(dbg_instr_wb), .dbg_alu_result(dbg_alu_result),
        .dbg_dmem_re(dbg_dmem_re), .dbg_dmem_we(dbg_dmem_we),
        .dbg_dmem_addr(dbg_dmem_addr), .dbg_dmem_wdata(dbg_dmem_wdata),
        .dbg_fwd_a(dbg_fwd_a), .dbg_fwd_b(dbg_fwd_b),
        .dbg_load_use_stall(dbg_load_use_stall), .dbg_flush(dbg_flush),
        .dbg_redirect(dbg_redirect), .dbg_halted(dbg_halted),
        .dbg_illegal_ex(dbg_illegal_ex),
        .dbg_wb_we(dbg_wb_we), .dbg_wb_rd(dbg_wb_rd), .dbg_wb_data(dbg_wb_data),
        .retire_valid(retire_valid), .retire_pc(retire_pc),
        .retire_instr(retire_instr), .retire_halt(retire_halt),
        .cycle_count(cycle_count), .retired_count(retired_count),
        .load_use_stall_count(load_use_stall_count), .redirect_count(redirect_count),
        .perf_done(perf_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;                       // 10 ns clock

    // ---------------- golden data and bookkeeping ----------------
    reg [31:0] exp_regs  [0:31];
    reg [31:0] exp_mem   [0:255];
    reg [31:0] exp_pc    [0:511];
    reg [31:0] exp_stats [0:3];                 // N, T (redirects), S (load-use stalls), cycles
    reg [31:0] ret_pc_log [0:511];

    integer ret_n;
    integer errors_test, errors_total, tests_failed;
    integer k, cyc, id;
    integer need_all_valid;
    reg     saw_all_valid;
    reg [3:0] fwd_seen;                         // bit n set when a forwarding select == n was used
    reg     x0_violation, overlap_violation, illegal_seen, pc_x_seen;
    real    cpi, ipc;

    // ---------------- always-on monitors ----------------
    always @(posedge clk) begin
        if (!reset) begin
            if (retire_valid && ret_n < 512) begin
                ret_pc_log[ret_n] = retire_pc;
                ret_n = ret_n + 1;
            end
            if (dbg_valid === 8'hFF)                      saw_all_valid = 1'b1;
            fwd_seen[dbg_fwd_a] = 1'b1;
            fwd_seen[dbg_fwd_b] = 1'b1;
            if (dut.u_regfile.regs[0] !== 32'd0)          x0_violation = 1'b1;
            if (dbg_load_use_stall && dbg_redirect)       overlap_violation = 1'b1;
            if (dbg_illegal_ex === 1'b1)                  illegal_seen = 1'b1;
            if (^dbg_pc === 1'bx)                         pc_x_seen = 1'b1;
        end
    end

    // ---------------- helper tasks ----------------
    task fail;
        input [8*60-1:0] msg;
        begin
            $display("    FAIL: %0s", msg);
            errors_test = errors_test + 1;
        end
    endtask

    task expect_reg;
        input integer r;
        input [31:0]  v;
        begin
            if (dut.u_regfile.regs[r] !== v) begin
                $display("    FAIL: x%0d = %h, hand-calculated value %h", r, dut.u_regfile.regs[r], v);
                errors_test = errors_test + 1;
            end
        end
    endtask

    task expect_mem;
        input integer w;
        input [31:0]  v;
        begin
            if (dut.u_dmem.mem[w] !== v) begin
                $display("    FAIL: mem[%0d] = %h, hand-calculated value %h", w, dut.u_dmem.mem[w], v);
                errors_test = errors_test + 1;
            end
        end
    endtask

    // load the program and its golden files (literal paths: ModelSim needs plain strings)
    task load_files;
        input integer t;
        begin
            case (t)
                1: begin
                    $readmemh("tests/t1_alu.hex",        dut.u_imem.mem);
                    $readmemh("tests/t1_alu_regs.hex",   exp_regs);
                    $readmemh("tests/t1_alu_mem.hex",    exp_mem);
                    $readmemh("tests/t1_alu_pc.hex",     exp_pc);
                    $readmemh("tests/t1_alu_stats.hex",  exp_stats);
                end
                2: begin
                    $readmemh("tests/t2_forward.hex",       dut.u_imem.mem);
                    $readmemh("tests/t2_forward_regs.hex",  exp_regs);
                    $readmemh("tests/t2_forward_mem.hex",   exp_mem);
                    $readmemh("tests/t2_forward_pc.hex",    exp_pc);
                    $readmemh("tests/t2_forward_stats.hex", exp_stats);
                end
                3: begin
                    $readmemh("tests/t3_loadstore.hex",       dut.u_imem.mem);
                    $readmemh("tests/t3_loadstore_regs.hex",  exp_regs);
                    $readmemh("tests/t3_loadstore_mem.hex",   exp_mem);
                    $readmemh("tests/t3_loadstore_pc.hex",    exp_pc);
                    $readmemh("tests/t3_loadstore_stats.hex", exp_stats);
                end
                4: begin
                    $readmemh("tests/t4_branch.hex",       dut.u_imem.mem);
                    $readmemh("tests/t4_branch_regs.hex",  exp_regs);
                    $readmemh("tests/t4_branch_mem.hex",   exp_mem);
                    $readmemh("tests/t4_branch_pc.hex",    exp_pc);
                    $readmemh("tests/t4_branch_stats.hex", exp_stats);
                end
                5: begin
                    $readmemh("tests/t5_jump.hex",       dut.u_imem.mem);
                    $readmemh("tests/t5_jump_regs.hex",  exp_regs);
                    $readmemh("tests/t5_jump_mem.hex",   exp_mem);
                    $readmemh("tests/t5_jump_pc.hex",    exp_pc);
                    $readmemh("tests/t5_jump_stats.hex", exp_stats);
                end
                6: begin
                    $readmemh("tests/t6_bench.hex",       dut.u_imem.mem);
                    $readmemh("tests/t6_bench_regs.hex",  exp_regs);
                    $readmemh("tests/t6_bench_mem.hex",   exp_mem);
                    $readmemh("tests/t6_bench_pc.hex",    exp_pc);
                    $readmemh("tests/t6_bench_stats.hex", exp_stats);
                end
                default: begin
                    $readmemh("tests/t7_system.hex",       dut.u_imem.mem);
                    $readmemh("tests/t7_system_regs.hex",  exp_regs);
                    $readmemh("tests/t7_system_mem.hex",   exp_mem);
                    $readmemh("tests/t7_system_pc.hex",    exp_pc);
                    $readmemh("tests/t7_system_stats.hex", exp_stats);
                end
            endcase
        end
    endtask

    // hand-calculated values (independent of the golden files)
    task spot_checks;
        input integer t;
        begin
            case (t)
                1: begin
                    expect_reg(3, 32'd12);        expect_reg(4, 32'd7);
                    expect_reg(8, 32'd640);       expect_reg(11, 32'hFFFFFFFF);
                    expect_reg(12, 32'h01FFFFFF); expect_reg(22, 32'hFFFFFFFC);
                    expect_reg(23, 32'h12345000); expect_reg(24, 32'h0000105C);
                    expect_reg(25, 32'd5);        expect_reg(26, 32'hFFFFFFFB);
                end
                2: begin
                    expect_reg(2, 2);   expect_reg(3, 3);   expect_reg(4, 5);   expect_reg(5, 6);
                    expect_reg(7, 11);  expect_reg(9, 21);  expect_reg(11, 31); expect_reg(13, 200);
                    expect_reg(14, 1);  expect_reg(15, 0);  expect_reg(18, 7);  expect_reg(23, 0);
                    expect_reg(24, 2);  expect_reg(25, 16);
                    expect_mem(0, 32'h55); expect_mem(1, 32'h66);
                end
                3: begin
                    expect_reg(4, 32'hFFFFFFF7);  expect_reg(7, 32'hFFFFFF81);
                    expect_reg(8, 32'h000000F7);  expect_reg(10, 32'hFFFFA5F7);
                    expect_reg(13, 32'h000081C3); expect_reg(15, 32'h44332211);
                    expect_reg(17, 32'h07FF07FF); expect_reg(18, 32'h81C3A500);
                    expect_reg(22, 32'h03874BEE); expect_reg(24, 32'h81C3A5F7);
                    expect_reg(28, 32'h0000004D); expect_reg(31, 2);
                    expect_mem(3, 32'h44332211);  expect_mem(7, 32'h81C3A5F7);
                end
                4: begin
                    expect_reg(10, 1); expect_reg(11, 2); expect_reg(12, 3); expect_reg(13, 4);
                    expect_reg(14, 5); expect_reg(15, 6); expect_reg(16, 7); expect_reg(17, 8);
                    expect_reg(18, 9); expect_reg(19, 10); expect_reg(21, 11); expect_reg(22, 12);
                    expect_reg(23, 13); expect_reg(24, 15); expect_reg(26, 14); expect_reg(29, 15);
                    expect_mem(0, 15);
                    expect_mem(1, 0);          // wrong-path store must not reach memory
                end
                5: begin
                    expect_reg(1, 4);  expect_reg(10, 1); expect_reg(12, 2); expect_reg(13, 3);
                    expect_reg(15, 4); expect_reg(19, 5); expect_reg(25, 6); expect_reg(29, 7);
                end
                6: begin
                    expect_reg(4, 92); expect_mem(0, 92);
                    expect_mem(16, 1); expect_mem(23, 22);      // source array (byte addr 64..92)
                    expect_mem(32, 1); expect_mem(39, 22);      // copy (byte addr 128..156)
                end
                default: begin
                    expect_reg(1, 1); expect_reg(2, 2);
                    expect_reg(3, 0); expect_reg(4, 0);        // after EBREAK: must not execute
                    expect_mem(0, 2); expect_mem(1, 0);
                end
            endcase
        end
    endtask

    // ---------------- one complete test ----------------
    task run_test;
        input integer t;
        begin
            errors_test = 0;
            case (t)
                1: begin $display("\n[T1] ALU / logic / shifts / LUI / AUIPC / x0   (also: sequential fetch)"); need_all_valid = 1; end
                2: begin $display("\n[T2] Data forwarding at every distance + priority + store data"); need_all_valid = 1; end
                3: begin $display("\n[T3] Loads, stores, sign extension, load-use hazards");            need_all_valid = 1; end
                4: begin $display("\n[T4] Branches: 6 types taken/not taken, flush, loops");            need_all_valid = 1; end
                5: begin $display("\n[T5] JAL / JALR / link / call-return / jalr hazards");             need_all_valid = 0; end
                6: begin $display("\n[T6] Benchmark: fill, sum (load-use), copy");                      need_all_valid = 1; end
                default: begin $display("\n[T7] FENCE, EBREAK halt, nothing after halt executes");      need_all_valid = 0; end
            endcase

            // ---- reset and load ----
            reset = 1'b1;
            load_files(t);
            for (k = 0; k < 256; k = k + 1) dut.u_dmem.mem[k] = 32'd0;
            ret_n = 0; saw_all_valid = 0; fwd_seen = 4'b0000;
            x0_violation = 0; overlap_violation = 0; illegal_seen = 0; pc_x_seen = 0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;

            // ---- run until the halt instruction retires ----
            cyc = 0;
            while (!perf_done && cyc < MAX_CYCLES) begin
                @(posedge clk); #1;
                cyc = cyc + 1;
                if (t == 1 && cyc <= 6 && dbg_pc !== (32'd4 * cyc))
                    fail("sequential fetch: PC did not advance by 4");
            end
            if (!perf_done) fail("TIMEOUT: halt instruction never retired");

            // keep clocking: anything fetched after the halt must be harmless
            repeat (12) @(posedge clk);
            #1;

            // ---- 1. architectural state vs golden model ----
            for (k = 0; k < 32; k = k + 1)
                if (dut.u_regfile.regs[k] !== exp_regs[k]) begin
                    $display("    FAIL: x%0d = %h, golden %h", k, dut.u_regfile.regs[k], exp_regs[k]);
                    errors_test = errors_test + 1;
                end
            for (k = 0; k < 256; k = k + 1)
                if (dut.u_dmem.mem[k] !== exp_mem[k]) begin
                    $display("    FAIL: mem[%0d] = %h, golden %h", k, dut.u_dmem.mem[k], exp_mem[k]);
                    errors_test = errors_test + 1;
                end

            // ---- 2. hand-calculated values ----
            spot_checks(t);

            // ---- 3. retirement order ----
            if (ret_n !== exp_stats[0]) begin
                $display("    FAIL: %0d instructions retired, expected %0d", ret_n, exp_stats[0]);
                errors_test = errors_test + 1;
            end
            for (k = 0; k < exp_stats[0] && k < 512; k = k + 1)
                if (ret_pc_log[k] !== exp_pc[k]) begin
                    $display("    FAIL: retire #%0d pc = %h, expected %h", k, ret_pc_log[k], exp_pc[k]);
                    errors_test = errors_test + 1;
                end

            // ---- 4. hazard / timing counters ----
            if (retired_count !== exp_stats[0]) begin
                $display("    FAIL: retired_count %0d, expected %0d", retired_count, exp_stats[0]);
                errors_test = errors_test + 1;
            end
            if (redirect_count !== exp_stats[1]) begin
                $display("    FAIL: redirects %0d, expected %0d", redirect_count, exp_stats[1]);
                errors_test = errors_test + 1;
            end
            if (load_use_stall_count !== exp_stats[2]) begin
                $display("    FAIL: load-use stalls %0d, expected %0d", load_use_stall_count, exp_stats[2]);
                errors_test = errors_test + 1;
            end
            if (cycle_count !== exp_stats[3]) begin
                $display("    FAIL: cycles %0d, expected %0d (N+7+S+4T)", cycle_count, exp_stats[3]);
                errors_test = errors_test + 1;
            end
            if (cyc !== cycle_count) fail("testbench cycle count differs from DUT cycle_count");

            // ---- 5. pipeline behaviour monitors ----
            if (need_all_valid && !saw_all_valid) fail("all 8 stages were never valid at the same time");
            if (t == 2 && fwd_seen[3:1] !== 3'b111) fail("T2 did not use MEM1, MEM2 and WB forwarding");
            if (x0_violation)      fail("x0 became non-zero");
            if (overlap_violation) fail("load-use stall and redirect asserted together");
            if (illegal_seen)      fail("illegal instruction flagged in EX");
            if (pc_x_seen)         fail("PC contained X or Z");

            // ---- report ----
            cpi = cycle_count;  cpi = cpi / retired_count;
            ipc = retired_count; ipc = ipc / cycle_count;
            $display("    cycles=%0d retired=%0d CPI=%0.3f IPC=%0.3f | load-use stalls=%0d | redirects=%0d (flush cycles=%0d)",
                     cycle_count, retired_count, cpi, ipc, load_use_stall_count,
                     redirect_count, 4 * redirect_count);
            if (errors_test == 0) $display("    T%0d PASS", t);
            else begin
                $display("    T%0d FAIL (%0d errors)", t, errors_test);
                tests_failed = tests_failed + 1;
            end
            errors_total = errors_total + errors_test;
        end
    endtask

    // ---------------- main sequence ----------------
    initial begin
        errors_total = 0; tests_failed = 0; errors_test = 0;
        ret_n = 0; fwd_seen = 4'b0000;
        x0_violation = 0; overlap_violation = 0; illegal_seen = 0; pc_x_seen = 0; saw_all_valid = 0;
        reset = 1'b1;

        $display("=====================================================================");
        $display(" 8-stage RV32I pipeline : self-checking verification");
        $display("=====================================================================");

        // ---- T0: reset behaviour ----
        repeat (3) @(posedge clk);
        #1;
        $display("\n[T0] Reset behaviour");
        if (dbg_pc !== 32'd0)          fail("PC is not 0 during reset");
        if (dbg_valid[7:1] !== 7'd0)   fail("pipeline stages are not empty during reset");
        if (retire_valid !== 1'b0)     fail("retire_valid during reset");
        if (cycle_count !== 32'd0 || retired_count !== 32'd0) fail("counters not cleared by reset");
        if (dbg_halted !== 1'b0)       fail("halted flag set during reset");
        for (k = 0; k < 32; k = k + 1)
            if (dut.u_regfile.regs[k] !== 32'd0) fail("register not cleared by reset");
        if (errors_test == 0) $display("    T0 PASS"); else tests_failed = tests_failed + 1;
        errors_total = errors_total + errors_test;

        for (id = 1; id <= NUM_TESTS; id = id + 1) run_test(id);

        $display("\n=====================================================================");
        if (errors_total == 0)
            $display(" ALL %0d TESTS PASSED  (T0..T%0d)", NUM_TESTS + 1, NUM_TESTS);
        else
            $display(" %0d TEST(S) FAILED, %0d error(s) in total", tests_failed, errors_total);
        $display("=====================================================================");
        $finish;
    end

endmodule
