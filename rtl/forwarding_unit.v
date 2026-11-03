`timescale 1ns/1ps
// EX stage: chooses where each ALU operand comes from.
//   0 = value read in RR stage      1 = MEM1 stage (EX_MEM1 register, ALU result)
//   2 = MEM2 stage (ALU result or freshly returned LOAD data)
//   3 = WB stage (value about to be written back)
// Priority is newest-first: MEM1 > MEM2 > WB.
// A load in MEM1 cannot forward (data not back yet). The hazard unit stalls so this
// case never reaches EX; the ~is_load term only keeps a wrong value from being used.
module forwarding_unit (
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    input  wire       ex_uses_rs1,
    input  wire       ex_uses_rs2,
    input  wire       mem1_valid, mem1_reg_write, mem1_is_load,
    input  wire [4:0] mem1_rd,
    input  wire       mem2_valid, mem2_reg_write,
    input  wire [4:0] mem2_rd,
    input  wire       wb_valid, wb_reg_write,
    input  wire [4:0] wb_rd,
    output wire [1:0] fwd_a,
    output wire [1:0] fwd_b
);
    wire m1_ok = mem1_valid & mem1_reg_write & ~mem1_is_load & (mem1_rd != 5'd0);
    wire m2_ok = mem2_valid & mem2_reg_write & (mem2_rd != 5'd0);
    wire w_ok  = wb_valid   & wb_reg_write   & (wb_rd   != 5'd0);

    assign fwd_a = ~ex_uses_rs1                 ? 2'd0 :
                   (m1_ok & (mem1_rd == ex_rs1)) ? 2'd1 :
                   (m2_ok & (mem2_rd == ex_rs1)) ? 2'd2 :
                   (w_ok  & (wb_rd   == ex_rs1)) ? 2'd3 : 2'd0;

    assign fwd_b = ~ex_uses_rs2                 ? 2'd0 :
                   (m1_ok & (mem1_rd == ex_rs2)) ? 2'd1 :
                   (m2_ok & (mem2_rd == ex_rs2)) ? 2'd2 :
                   (w_ok  & (wb_rd   == ex_rs2)) ? 2'd3 : 2'd0;
endmodule
