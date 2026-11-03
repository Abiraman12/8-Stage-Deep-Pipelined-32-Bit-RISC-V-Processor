`timescale 1ns/1ps
// =============================================================================
// riscv_8stage_top : 8-stage pipelined RV32I processor
//
//   IF1 -> [IF1_IF2] -> IF2 -> [IF2_ID] -> ID -> [ID_RR] -> RR -> [RR_EX]
//       -> EX -> [EX_MEM1] -> MEM1 -> [MEM1_MEM2] -> MEM2 -> [MEM2_WB] -> WB
//
// Signal prefixes (outputs of each pipeline register, i.e. inputs of the next stage):
//   f12_ = IF1_IF2   f2d_ = IF2_ID   d2r_ = ID_RR   r2e_ = RR_EX
//   e2m_ = EX_MEM1   m12_ = MEM1_MEM2   m2w_ = MEM2_WB
//
// Hazard policy
//   * Data  : forwarding into EX from MEM1 / MEM2 / WB, register-file write bypass,
//             1-cycle stall for a load followed by its consumer (load-use).
//   * Control: static predict-not-taken. Branch / JAL / JALR resolve in EX, so the
//             4 younger instructions (RR, ID, IF2, IF1) are flushed: penalty 4 cycles.
//   * ECALL / EBREAK: treated as "halt" (simplification, see docs).
// =============================================================================
module riscv_8stage_top #(
    parameter IMEM_FILE = ""          // optional $readmemh program file
) (
    input  wire        clk,
    input  wire        reset,         // synchronous, active high

    // ---------------- debug / verification outputs ----------------
    output wire [31:0] dbg_pc,                // PC being fetched (IF1)
    output wire [7:0]  dbg_valid,             // {WB,MEM2,MEM1,EX,RR,ID,IF2,IF1}
    output wire [31:0] dbg_instr_if2,
    output wire [31:0] dbg_instr_id,
    output wire [31:0] dbg_instr_rr,
    output wire [31:0] dbg_instr_ex,
    output wire [31:0] dbg_instr_mem1,
    output wire [31:0] dbg_instr_mem2,
    output wire [31:0] dbg_instr_wb,
    output wire [31:0] dbg_alu_result,
    output wire        dbg_dmem_re,
    output wire        dbg_dmem_we,
    output wire [31:0] dbg_dmem_addr,
    output wire [31:0] dbg_dmem_wdata,
    output wire [1:0]  dbg_fwd_a,
    output wire [1:0]  dbg_fwd_b,
    output wire        dbg_load_use_stall,
    output wire        dbg_flush,             // wrong-path flush (branch/jump/halt)
    output wire        dbg_redirect,
    output wire        dbg_halted,
    output wire        dbg_illegal_ex,
    output wire        dbg_wb_we,
    output wire [4:0]  dbg_wb_rd,
    output wire [31:0] dbg_wb_data,

    // instruction retirement
    output wire        retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_instr,
    output wire        retire_halt,           // the retiring instruction is ECALL/EBREAK

    // performance counters (stop counting when the halt instruction retires)
    output reg  [31:0] cycle_count,
    output reg  [31:0] retired_count,
    output reg  [31:0] load_use_stall_count,
    output reg  [31:0] redirect_count,
    output reg         perf_done
);

    // ------------------------------------------------------------------
    // Global control wires
    // ------------------------------------------------------------------
    wire        load_use_stall;
    wire        br_redirect, br_taken, br_halt_req;
    wire [31:0] br_target;
    reg         halted;

    wire flush_younger = br_redirect | br_halt_req | halted;        // IF1_IF2, IF2_ID, ID_RR
    wire flush_rr_ex   = flush_younger | load_use_stall;            // + bubble on stall
    wire pc_stall      = load_use_stall | halted | br_halt_req;

    // ==================================================================
    // Stage 1 : IF1  (program counter, next PC)
    // ==================================================================
    wire [31:0] pc, pc_plus4, next_pc;

    program_counter u_pc (
        .clk(clk), .reset(reset), .stall(pc_stall),
        .redirect(br_redirect), .redirect_target(br_target),
        .pc(pc), .pc_plus4(pc_plus4), .next_pc(next_pc)
    );

    // ---------------- IF1_IF2 ----------------
    wire        f12_valid;
    wire [31:0] f12_pc;

    if1_if2_register u_if1_if2 (
        .clk(clk), .reset(reset), .flush(flush_younger), .stall(load_use_stall),
        .in_valid(1'b1), .in_pc(pc),
        .out_valid(f12_valid), .out_pc(f12_pc)
    );

    // ==================================================================
    // Stage 2 : IF2  (instruction memory access)
    // ==================================================================
    wire [31:0] if2_instr;

    instruction_memory #(.INIT_FILE(IMEM_FILE)) u_imem (
        .addr(f12_pc), .instr(if2_instr)
    );

    // ---------------- IF2_ID ----------------
    wire        f2d_valid;
    wire [31:0] f2d_pc, f2d_instr;

    if2_id_register u_if2_id (
        .clk(clk), .reset(reset), .flush(flush_younger), .stall(load_use_stall),
        .in_valid(f12_valid), .in_pc(f12_pc), .in_instr(if2_instr),
        .out_valid(f2d_valid), .out_pc(f2d_pc), .out_instr(f2d_instr)
    );

    // ==================================================================
    // Stage 3 : ID  (decode, control, immediate)
    // ==================================================================
    wire [6:0]  id_opcode, id_funct7;
    wire [4:0]  id_rd, id_rs1, id_rs2;
    wire [2:0]  id_funct3, id_fmt;
    wire        id_is_lui, id_is_auipc, id_is_jal, id_is_jalr, id_is_branch;
    wire        id_is_load, id_is_store, id_is_op_imm, id_is_op, id_is_fence, id_is_system;
    wire        id_uses_rs1, id_uses_rs2, id_illegal;
    wire        id_reg_write, id_mem_read, id_mem_write;
    wire        id_alu_src_a_pc, id_alu_src_b_imm;
    wire [3:0]  id_alu_op;
    wire        id_branch, id_jal, id_jalr, id_system;
    wire [31:0] id_imm;

    instruction_decoder u_decoder (
        .instr(f2d_instr),
        .opcode(id_opcode), .rd(id_rd), .funct3(id_funct3), .rs1(id_rs1), .rs2(id_rs2),
        .funct7(id_funct7),
        .is_lui(id_is_lui), .is_auipc(id_is_auipc), .is_jal(id_is_jal), .is_jalr(id_is_jalr),
        .is_branch(id_is_branch), .is_load(id_is_load), .is_store(id_is_store),
        .is_op_imm(id_is_op_imm), .is_op(id_is_op), .is_fence(id_is_fence),
        .is_system(id_is_system),
        .uses_rs1(id_uses_rs1), .uses_rs2(id_uses_rs2),
        .fmt(id_fmt), .illegal(id_illegal)
    );

    control_unit u_control (
        .is_lui(id_is_lui), .is_auipc(id_is_auipc), .is_jal(id_is_jal), .is_jalr(id_is_jalr),
        .is_branch(id_is_branch), .is_load(id_is_load), .is_store(id_is_store),
        .is_op_imm(id_is_op_imm), .is_op(id_is_op), .is_system(id_is_system),
        .funct3(id_funct3), .funct7_5(f2d_instr[30]), .illegal(id_illegal),
        .reg_write(id_reg_write), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .alu_src_a_pc(id_alu_src_a_pc), .alu_src_b_imm(id_alu_src_b_imm),
        .alu_op(id_alu_op),
        .branch_o(id_branch), .jal_o(id_jal), .jalr_o(id_jalr), .system_o(id_system)
    );

    immediate_generator u_immgen (
        .instr(f2d_instr), .fmt(id_fmt), .imm(id_imm)
    );

    // ---------------- ID_RR ----------------
    wire        d2r_valid;
    wire [31:0] d2r_pc, d2r_instr, d2r_imm;
    wire [4:0]  d2r_rs1_addr, d2r_rs2_addr, d2r_rd_addr;
    wire [2:0]  d2r_funct3;
    wire        d2r_uses_rs1, d2r_uses_rs2, d2r_reg_write, d2r_mem_read, d2r_mem_write;
    wire        d2r_alu_src_a_pc, d2r_alu_src_b_imm;
    wire [3:0]  d2r_alu_op;
    wire        d2r_is_branch, d2r_is_jal, d2r_is_jalr, d2r_is_system, d2r_illegal;

    id_rr_register u_id_rr (
        .clk(clk), .reset(reset), .flush(flush_younger), .stall(load_use_stall),
        .in_valid(f2d_valid), .in_pc(f2d_pc), .in_instr(f2d_instr),
        .in_rs1_addr(id_rs1), .in_rs2_addr(id_rs2), .in_rd_addr(id_rd),
        .in_imm(id_imm), .in_funct3(id_funct3),
        .in_uses_rs1(id_uses_rs1), .in_uses_rs2(id_uses_rs2),
        .in_reg_write(id_reg_write), .in_mem_read(id_mem_read), .in_mem_write(id_mem_write),
        .in_alu_src_a_pc(id_alu_src_a_pc), .in_alu_src_b_imm(id_alu_src_b_imm),
        .in_alu_op(id_alu_op),
        .in_is_branch(id_branch), .in_is_jal(id_jal), .in_is_jalr(id_jalr),
        .in_is_system(id_system), .in_illegal(id_illegal),
        .out_valid(d2r_valid), .out_pc(d2r_pc), .out_instr(d2r_instr),
        .out_rs1_addr(d2r_rs1_addr), .out_rs2_addr(d2r_rs2_addr), .out_rd_addr(d2r_rd_addr),
        .out_imm(d2r_imm), .out_funct3(d2r_funct3),
        .out_uses_rs1(d2r_uses_rs1), .out_uses_rs2(d2r_uses_rs2),
        .out_reg_write(d2r_reg_write), .out_mem_read(d2r_mem_read), .out_mem_write(d2r_mem_write),
        .out_alu_src_a_pc(d2r_alu_src_a_pc), .out_alu_src_b_imm(d2r_alu_src_b_imm),
        .out_alu_op(d2r_alu_op),
        .out_is_branch(d2r_is_branch), .out_is_jal(d2r_is_jal), .out_is_jalr(d2r_is_jalr),
        .out_is_system(d2r_is_system), .out_illegal(d2r_illegal)
    );

    // ==================================================================
    // Stage 4 : RR  (register file read; the write port belongs to WB)
    // ==================================================================
    wire [31:0] rr_rs1_data, rr_rs2_data;
    wire        wb_we;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    register_file u_regfile (
        .clk(clk), .reset(reset),
        .we(wb_we), .waddr(wb_rd), .wdata(wb_data),
        .raddr1(d2r_rs1_addr), .raddr2(d2r_rs2_addr),
        .rdata1(rr_rs1_data), .rdata2(rr_rs2_data)
    );

    // Load-use hazard detection (instruction in RR vs. load in EX)
    wire        r2e_valid, r2e_mem_read;
    wire [4:0]  r2e_rd_addr;

    hazard_detection_unit u_hazard (
        .rr_valid(d2r_valid), .rr_rs1(d2r_rs1_addr), .rr_rs2(d2r_rs2_addr),
        .rr_uses_rs1(d2r_uses_rs1), .rr_uses_rs2(d2r_uses_rs2),
        .ex_valid(r2e_valid), .ex_is_load(r2e_mem_read), .ex_rd(r2e_rd_addr),
        .load_use_stall(load_use_stall)
    );

    // ---------------- RR_EX ----------------
    wire [31:0] r2e_pc, r2e_instr, r2e_imm, r2e_rs1_data, r2e_rs2_data;
    wire [4:0]  r2e_rs1_addr, r2e_rs2_addr;
    wire [2:0]  r2e_funct3;
    wire        r2e_uses_rs1, r2e_uses_rs2, r2e_reg_write, r2e_mem_write;
    wire        r2e_alu_src_a_pc, r2e_alu_src_b_imm;
    wire [3:0]  r2e_alu_op;
    wire        r2e_is_branch, r2e_is_jal, r2e_is_jalr, r2e_is_system, r2e_illegal;

    rr_ex_register u_rr_ex (
        .clk(clk), .reset(reset), .flush(flush_rr_ex), .stall(1'b0),
        .in_valid(d2r_valid), .in_pc(d2r_pc), .in_instr(d2r_instr),
        .in_rs1_addr(d2r_rs1_addr), .in_rs2_addr(d2r_rs2_addr), .in_rd_addr(d2r_rd_addr),
        .in_imm(d2r_imm), .in_funct3(d2r_funct3),
        .in_uses_rs1(d2r_uses_rs1), .in_uses_rs2(d2r_uses_rs2),
        .in_reg_write(d2r_reg_write), .in_mem_read(d2r_mem_read), .in_mem_write(d2r_mem_write),
        .in_alu_src_a_pc(d2r_alu_src_a_pc), .in_alu_src_b_imm(d2r_alu_src_b_imm),
        .in_alu_op(d2r_alu_op),
        .in_is_branch(d2r_is_branch), .in_is_jal(d2r_is_jal), .in_is_jalr(d2r_is_jalr),
        .in_is_system(d2r_is_system), .in_illegal(d2r_illegal),
        .in_rs1_data(rr_rs1_data), .in_rs2_data(rr_rs2_data),
        .out_valid(r2e_valid), .out_pc(r2e_pc), .out_instr(r2e_instr),
        .out_rs1_addr(r2e_rs1_addr), .out_rs2_addr(r2e_rs2_addr), .out_rd_addr(r2e_rd_addr),
        .out_imm(r2e_imm), .out_funct3(r2e_funct3),
        .out_uses_rs1(r2e_uses_rs1), .out_uses_rs2(r2e_uses_rs2),
        .out_reg_write(r2e_reg_write), .out_mem_read(r2e_mem_read), .out_mem_write(r2e_mem_write),
        .out_alu_src_a_pc(r2e_alu_src_a_pc), .out_alu_src_b_imm(r2e_alu_src_b_imm),
        .out_alu_op(r2e_alu_op),
        .out_is_branch(r2e_is_branch), .out_is_jal(r2e_is_jal), .out_is_jalr(r2e_is_jalr),
        .out_is_system(r2e_is_system), .out_illegal(r2e_illegal),
        .out_rs1_data(r2e_rs1_data), .out_rs2_data(r2e_rs2_data)
    );

    // ==================================================================
    // Stage 5 : EX  (forwarding, ALU, branch / jump resolution)
    // ==================================================================
    // Producers in later stages (declared here, driven further below)
    wire        e2m_valid, e2m_reg_write, e2m_mem_read, e2m_mem_write;
    wire [4:0]  e2m_rd_addr;
    wire [2:0]  e2m_funct3;
    wire [31:0] e2m_pc, e2m_instr, e2m_alu_result, e2m_store_data;
    wire        m12_valid, m12_reg_write, m12_mem_read;
    wire [4:0]  m12_rd_addr;
    wire [2:0]  m12_funct3;
    wire [31:0] m12_pc, m12_instr, m12_alu_result;
    wire        m2w_valid, m2w_reg_write, m2w_mem_to_reg;
    wire [4:0]  m2w_rd_addr;
    wire [31:0] m2w_pc, m2w_instr, m2w_alu_result, m2w_load_data;
    wire [31:0] m2_load_data;

    // value available in MEM2: load data (just returned) or the ALU result
    wire [31:0] mem2_result = m12_mem_read ? m2_load_data : m12_alu_result;

    wire [1:0] fwd_a, fwd_b;

    forwarding_unit u_forward (
        .ex_rs1(r2e_rs1_addr), .ex_rs2(r2e_rs2_addr),
        .ex_uses_rs1(r2e_uses_rs1), .ex_uses_rs2(r2e_uses_rs2),
        .mem1_valid(e2m_valid), .mem1_reg_write(e2m_reg_write),
        .mem1_is_load(e2m_mem_read), .mem1_rd(e2m_rd_addr),
        .mem2_valid(m12_valid), .mem2_reg_write(m12_reg_write), .mem2_rd(m12_rd_addr),
        .wb_valid(m2w_valid), .wb_reg_write(m2w_reg_write), .wb_rd(m2w_rd_addr),
        .fwd_a(fwd_a), .fwd_b(fwd_b)
    );

    reg [31:0] ex_rs1_fwd, ex_rs2_fwd;

    always @(*) begin
        case (fwd_a)
            2'd1:    ex_rs1_fwd = e2m_alu_result;
            2'd2:    ex_rs1_fwd = mem2_result;
            2'd3:    ex_rs1_fwd = wb_data;
            default: ex_rs1_fwd = r2e_rs1_data;
        endcase
        case (fwd_b)
            2'd1:    ex_rs2_fwd = e2m_alu_result;
            2'd2:    ex_rs2_fwd = mem2_result;
            2'd3:    ex_rs2_fwd = wb_data;
            default: ex_rs2_fwd = r2e_rs2_data;
        endcase
    end

    wire [31:0] alu_a = r2e_alu_src_a_pc  ? r2e_pc  : ex_rs1_fwd;
    wire [31:0] alu_b = r2e_alu_src_b_imm ? r2e_imm : ex_rs2_fwd;
    wire [31:0] alu_result;

    alu u_alu (.a(alu_a), .b(alu_b), .alu_op(r2e_alu_op), .result(alu_result));

    // JAL / JALR write the link address PC+4 instead of an ALU result
    wire [31:0] ex_result = (r2e_is_jal | r2e_is_jalr) ? (r2e_pc + 32'd4) : alu_result;

    branch_control u_branch (
        .valid(r2e_valid), .is_branch(r2e_is_branch), .is_jal(r2e_is_jal),
        .is_jalr(r2e_is_jalr), .is_system(r2e_is_system), .funct3(r2e_funct3),
        .rs1_val(ex_rs1_fwd), .rs2_val(ex_rs2_fwd), .pc(r2e_pc), .imm(r2e_imm),
        .redirect(br_redirect), .redirect_target(br_target),
        .branch_taken(br_taken), .halt_req(br_halt_req)
    );

    // ---------------- EX_MEM1 ----------------
    ex_mem1_register u_ex_mem1 (
        .clk(clk), .reset(reset), .flush(1'b0), .stall(1'b0),
        .in_valid(r2e_valid), .in_pc(r2e_pc), .in_instr(r2e_instr),
        .in_rd_addr(r2e_rd_addr), .in_funct3(r2e_funct3),
        .in_reg_write(r2e_reg_write), .in_mem_read(r2e_mem_read), .in_mem_write(r2e_mem_write),
        .in_alu_result(ex_result), .in_store_data(ex_rs2_fwd),
        .out_valid(e2m_valid), .out_pc(e2m_pc), .out_instr(e2m_instr),
        .out_rd_addr(e2m_rd_addr), .out_funct3(e2m_funct3),
        .out_reg_write(e2m_reg_write), .out_mem_read(e2m_mem_read), .out_mem_write(e2m_mem_write),
        .out_alu_result(e2m_alu_result), .out_store_data(e2m_store_data)
    );

    // ==================================================================
    // Stage 6 : MEM1  (data memory request)
    // ==================================================================
    wire        m1_re = e2m_valid & e2m_mem_read;
    wire        m1_we = e2m_valid & e2m_mem_write;
    reg  [31:0] m1_wdata;
    reg  [3:0]  m1_wstrb;

    // Store data preparation: replicate the byte / halfword into its lane
    always @(*) begin
        case (e2m_funct3[1:0])
            2'b00: begin                                   // SB
                m1_wdata = {4{e2m_store_data[7:0]}};
                m1_wstrb = 4'b0001 << e2m_alu_result[1:0];
            end
            2'b01: begin                                   // SH
                m1_wdata = {2{e2m_store_data[15:0]}};
                m1_wstrb = e2m_alu_result[1] ? 4'b1100 : 4'b0011;
            end
            default: begin                                 // SW
                m1_wdata = e2m_store_data;
                m1_wstrb = 4'b1111;
            end
        endcase
    end

    wire [31:0] m2_raw_rdata;

    data_memory u_dmem (
        .clk(clk), .req_re(m1_re), .req_we(m1_we),
        .addr(e2m_alu_result), .wdata(m1_wdata), .wstrb(m1_wstrb),
        .rdata(m2_raw_rdata)
    );

    // ---------------- MEM1_MEM2 ----------------
    mem1_mem2_register u_mem1_mem2 (
        .clk(clk), .reset(reset), .flush(1'b0), .stall(1'b0),
        .in_valid(e2m_valid), .in_pc(e2m_pc), .in_instr(e2m_instr),
        .in_rd_addr(e2m_rd_addr), .in_funct3(e2m_funct3),
        .in_reg_write(e2m_reg_write), .in_mem_read(e2m_mem_read),
        .in_alu_result(e2m_alu_result),
        .out_valid(m12_valid), .out_pc(m12_pc), .out_instr(m12_instr),
        .out_rd_addr(m12_rd_addr), .out_funct3(m12_funct3),
        .out_reg_write(m12_reg_write), .out_mem_read(m12_mem_read),
        .out_alu_result(m12_alu_result)
    );

    // ==================================================================
    // Stage 7 : MEM2  (memory response, byte / halfword extraction)
    // ==================================================================
    load_extender u_load_ext (
        .raw_word(m2_raw_rdata), .addr_lo(m12_alu_result[1:0]),
        .funct3(m12_funct3), .load_data(m2_load_data)
    );

    // ---------------- MEM2_WB ----------------
    mem2_wb_register u_mem2_wb (
        .clk(clk), .reset(reset), .flush(1'b0), .stall(1'b0),
        .in_valid(m12_valid), .in_pc(m12_pc), .in_instr(m12_instr),
        .in_rd_addr(m12_rd_addr), .in_reg_write(m12_reg_write),
        .in_mem_to_reg(m12_mem_read), .in_alu_result(m12_alu_result),
        .in_load_data(m2_load_data),
        .out_valid(m2w_valid), .out_pc(m2w_pc), .out_instr(m2w_instr),
        .out_rd_addr(m2w_rd_addr), .out_reg_write(m2w_reg_write),
        .out_mem_to_reg(m2w_mem_to_reg), .out_alu_result(m2w_alu_result),
        .out_load_data(m2w_load_data)
    );

    // ==================================================================
    // Stage 8 : WB  (select result, write register file, retire)
    // ==================================================================
    assign wb_data = m2w_mem_to_reg ? m2w_load_data : m2w_alu_result;
    assign wb_rd   = m2w_rd_addr;
    assign wb_we   = m2w_valid & m2w_reg_write;

    assign retire_valid = m2w_valid;
    assign retire_pc    = m2w_pc;
    assign retire_instr = m2w_instr;
    assign retire_halt  = m2w_valid & ((m2w_instr == 32'h0000_0073) | (m2w_instr == 32'h0010_0073));

    // ------------------------------------------------------------------
    // Halt state: ECALL/EBREAK in EX stops instruction fetch for good
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset)            halted <= 1'b0;
        else if (br_halt_req) halted <= 1'b1;
    end

    // ------------------------------------------------------------------
    // Performance counters
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            cycle_count          <= 32'd0;
            retired_count        <= 32'd0;
            load_use_stall_count <= 32'd0;
            redirect_count       <= 32'd0;
            perf_done            <= 1'b0;
        end else if (!perf_done) begin
            cycle_count <= cycle_count + 32'd1;
            if (retire_valid)   retired_count        <= retired_count + 32'd1;
            if (load_use_stall) load_use_stall_count <= load_use_stall_count + 32'd1;
            if (br_redirect)    redirect_count       <= redirect_count + 32'd1;
            if (retire_halt)    perf_done            <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Debug outputs
    // ------------------------------------------------------------------
    assign dbg_pc             = pc;
    assign dbg_valid          = {m2w_valid, m12_valid, e2m_valid, r2e_valid,
                                 d2r_valid, f2d_valid, f12_valid, ~halted};
    assign dbg_instr_if2      = if2_instr;
    assign dbg_instr_id       = f2d_instr;
    assign dbg_instr_rr       = d2r_instr;
    assign dbg_instr_ex       = r2e_instr;
    assign dbg_instr_mem1     = e2m_instr;
    assign dbg_instr_mem2     = m12_instr;
    assign dbg_instr_wb       = m2w_instr;
    assign dbg_alu_result     = alu_result;
    assign dbg_dmem_re        = m1_re;
    assign dbg_dmem_we        = m1_we;
    assign dbg_dmem_addr      = e2m_alu_result;
    assign dbg_dmem_wdata     = m1_wdata;
    assign dbg_fwd_a          = fwd_a;
    assign dbg_fwd_b          = fwd_b;
    assign dbg_load_use_stall = load_use_stall;
    assign dbg_flush          = flush_younger;
    assign dbg_redirect       = br_redirect;
    assign dbg_halted         = halted;
    assign dbg_illegal_ex     = r2e_valid & r2e_illegal;
    assign dbg_wb_we          = wb_we;
    assign dbg_wb_rd          = wb_rd;
    assign dbg_wb_data        = wb_data;

endmodule
