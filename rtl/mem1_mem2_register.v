`timescale 1ns/1ps
// Pipeline register MEM1 -> MEM2: address / result and load control (data memory response is registered inside data_memory).
// Priority: reset > flush (becomes a bubble, valid = 0) > stall (hold) > load new values.
module mem1_mem2_register (
    input  wire clk,
    input  wire reset,   // synchronous, active high
    input  wire flush,   // turn the contents into a bubble
    input  wire stall,   // keep the current contents
    input  wire         in_valid,
    input  wire [31:0]  in_pc,
    input  wire [31:0]  in_instr,
    input  wire [4:0]   in_rd_addr,
    input  wire [2:0]   in_funct3,
    input  wire         in_reg_write,
    input  wire         in_mem_read,
    input  wire [31:0]  in_alu_result,
    output reg          out_valid,
    output reg  [31:0]  out_pc,
    output reg  [31:0]  out_instr,
    output reg  [4:0]   out_rd_addr,
    output reg  [2:0]   out_funct3,
    output reg          out_reg_write,
    output reg          out_mem_read,
    output reg  [31:0]  out_alu_result
);
    always @(posedge clk) begin
        if (reset || flush) begin
            out_valid <= 1'd0;
            out_pc <= 32'd0;
            out_instr <= 32'h0000_0013;
            out_rd_addr <= 5'd0;
            out_funct3 <= 3'd0;
            out_reg_write <= 1'd0;
            out_mem_read <= 1'd0;
            out_alu_result <= 32'd0;
        end else if (!stall) begin
            out_valid <= in_valid;
            out_pc <= in_pc;
            out_instr <= in_instr;
            out_rd_addr <= in_rd_addr;
            out_funct3 <= in_funct3;
            out_reg_write <= in_reg_write;
            out_mem_read <= in_mem_read;
            out_alu_result <= in_alu_result;
        end
    end
endmodule
