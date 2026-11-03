`timescale 1ns/1ps
// EX stage: branch comparison, branch/jump target generation, redirect decision,
// and ECALL/EBREAK halt request. Operands arrive already forwarded.
module branch_control (
    input  wire        valid,          // EX stage holds a real instruction
    input  wire        is_branch,
    input  wire        is_jal,
    input  wire        is_jalr,
    input  wire        is_system,
    input  wire [2:0]  funct3,
    input  wire [31:0] rs1_val,        // forwarded rs1
    input  wire [31:0] rs2_val,        // forwarded rs2
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    output wire        redirect,       // PC must change (taken branch, JAL, JALR)
    output wire [31:0] redirect_target,
    output wire        branch_taken,   // conditional branch taken (statistics)
    output wire        halt_req        // ECALL / EBREAK reached EX
);
    wire signed [31:0] a_s = rs1_val;
    wire signed [31:0] b_s = rs2_val;
    reg cond;

    always @(*) begin
        case (funct3)
            3'b000:  cond = (rs1_val == rs2_val);   // BEQ
            3'b001:  cond = (rs1_val != rs2_val);   // BNE
            3'b100:  cond = (a_s < b_s);            // BLT
            3'b101:  cond = (a_s >= b_s);           // BGE
            3'b110:  cond = (rs1_val < rs2_val);    // BLTU
            3'b111:  cond = (rs1_val >= rs2_val);   // BGEU
            default: cond = 1'b0;
        endcase
    end

    wire [31:0] pc_rel_target = pc + imm;                   // branch and JAL
    wire [31:0] jalr_sum      = rs1_val + imm;
    wire [31:0] jalr_target   = {jalr_sum[31:1], 1'b0};     // JALR clears bit 0

    assign branch_taken    = valid & is_branch & cond;
    assign redirect        = branch_taken | (valid & is_jal) | (valid & is_jalr);
    assign redirect_target = is_jalr ? jalr_target : pc_rel_target;
    assign halt_req        = valid & is_system;
endmodule
