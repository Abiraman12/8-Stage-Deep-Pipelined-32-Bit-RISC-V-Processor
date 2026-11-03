`timescale 1ns/1ps
// Pipeline register IF2 -> ID: fetched instruction with its PC.
// Priority: reset > flush (becomes a bubble, valid = 0) > stall (hold) > load new values.
module if2_id_register (
    input  wire clk,
    input  wire reset,   // synchronous, active high
    input  wire flush,   // turn the contents into a bubble
    input  wire stall,   // keep the current contents
    input  wire         in_valid,
    input  wire [31:0]  in_pc,
    input  wire [31:0]  in_instr,
    output reg          out_valid,
    output reg  [31:0]  out_pc,
    output reg  [31:0]  out_instr
);
    always @(posedge clk) begin
        if (reset || flush) begin
            out_valid <= 1'd0;
            out_pc <= 32'd0;
            out_instr <= 32'h0000_0013;
        end else if (!stall) begin
            out_valid <= in_valid;
            out_pc <= in_pc;
            out_instr <= in_instr;
        end
    end
endmodule
