`timescale 1ns/1ps
// Pipeline register RR -> EX: as ID_RR plus the two register operands.
// Priority: reset > flush (becomes a bubble, valid = 0) > stall (hold) > load new values.
module rr_ex_register (
    input  wire clk,
    input  wire reset,   // synchronous, active high
    input  wire flush,   // turn the contents into a bubble
    input  wire stall,   // keep the current contents
    input  wire         in_valid,
    input  wire [31:0]  in_pc,
    input  wire [31:0]  in_instr,
    input  wire [4:0]   in_rs1_addr,
    input  wire [4:0]   in_rs2_addr,
    input  wire [4:0]   in_rd_addr,
    input  wire [31:0]  in_imm,
    input  wire [2:0]   in_funct3,
    input  wire         in_uses_rs1,
    input  wire         in_uses_rs2,
    input  wire         in_reg_write,
    input  wire         in_mem_read,
    input  wire         in_mem_write,
    input  wire         in_alu_src_a_pc,
    input  wire         in_alu_src_b_imm,
    input  wire [3:0]   in_alu_op,
    input  wire         in_is_branch,
    input  wire         in_is_jal,
    input  wire         in_is_jalr,
    input  wire         in_is_system,
    input  wire         in_illegal,
    input  wire [31:0]  in_rs1_data,
    input  wire [31:0]  in_rs2_data,
    output reg          out_valid,
    output reg  [31:0]  out_pc,
    output reg  [31:0]  out_instr,
    output reg  [4:0]   out_rs1_addr,
    output reg  [4:0]   out_rs2_addr,
    output reg  [4:0]   out_rd_addr,
    output reg  [31:0]  out_imm,
    output reg  [2:0]   out_funct3,
    output reg          out_uses_rs1,
    output reg          out_uses_rs2,
    output reg          out_reg_write,
    output reg          out_mem_read,
    output reg          out_mem_write,
    output reg          out_alu_src_a_pc,
    output reg          out_alu_src_b_imm,
    output reg  [3:0]   out_alu_op,
    output reg          out_is_branch,
    output reg          out_is_jal,
    output reg          out_is_jalr,
    output reg          out_is_system,
    output reg          out_illegal,
    output reg  [31:0]  out_rs1_data,
    output reg  [31:0]  out_rs2_data
);
    always @(posedge clk) begin
        if (reset || flush) begin
            out_valid <= 1'd0;
            out_pc <= 32'd0;
            out_instr <= 32'h0000_0013;
            out_rs1_addr <= 5'd0;
            out_rs2_addr <= 5'd0;
            out_rd_addr <= 5'd0;
            out_imm <= 32'd0;
            out_funct3 <= 3'd0;
            out_uses_rs1 <= 1'd0;
            out_uses_rs2 <= 1'd0;
            out_reg_write <= 1'd0;
            out_mem_read <= 1'd0;
            out_mem_write <= 1'd0;
            out_alu_src_a_pc <= 1'd0;
            out_alu_src_b_imm <= 1'd0;
            out_alu_op <= 4'd0;
            out_is_branch <= 1'd0;
            out_is_jal <= 1'd0;
            out_is_jalr <= 1'd0;
            out_is_system <= 1'd0;
            out_illegal <= 1'd0;
            out_rs1_data <= 32'd0;
            out_rs2_data <= 32'd0;
        end else if (!stall) begin
            out_valid <= in_valid;
            out_pc <= in_pc;
            out_instr <= in_instr;
            out_rs1_addr <= in_rs1_addr;
            out_rs2_addr <= in_rs2_addr;
            out_rd_addr <= in_rd_addr;
            out_imm <= in_imm;
            out_funct3 <= in_funct3;
            out_uses_rs1 <= in_uses_rs1;
            out_uses_rs2 <= in_uses_rs2;
            out_reg_write <= in_reg_write;
            out_mem_read <= in_mem_read;
            out_mem_write <= in_mem_write;
            out_alu_src_a_pc <= in_alu_src_a_pc;
            out_alu_src_b_imm <= in_alu_src_b_imm;
            out_alu_op <= in_alu_op;
            out_is_branch <= in_is_branch;
            out_is_jal <= in_is_jal;
            out_is_jalr <= in_is_jalr;
            out_is_system <= in_is_system;
            out_illegal <= in_illegal;
            out_rs1_data <= in_rs1_data;
            out_rs2_data <= in_rs2_data;
        end
    end
endmodule
