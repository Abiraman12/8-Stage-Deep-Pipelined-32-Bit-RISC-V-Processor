`timescale 1ns/1ps
// Load-use hazard detection.
// The instruction in RR needs a register that a LOAD currently in EX will produce.
// The load data only returns in MEM2 (two stages later), so RR must wait one cycle:
// PC / IF1_IF2 / IF2_ID / ID_RR hold, and a bubble enters RR_EX.
module hazard_detection_unit (
    input  wire       rr_valid,
    input  wire [4:0] rr_rs1,
    input  wire [4:0] rr_rs2,
    input  wire       rr_uses_rs1,
    input  wire       rr_uses_rs2,
    input  wire       ex_valid,
    input  wire       ex_is_load,
    input  wire [4:0] ex_rd,
    output wire       load_use_stall
);
    assign load_use_stall = rr_valid & ex_valid & ex_is_load & (ex_rd != 5'd0) &
                            ((rr_uses_rs1 & (rr_rs1 == ex_rd)) |
                             (rr_uses_rs2 & (rr_rs2 == ex_rd)));
endmodule
