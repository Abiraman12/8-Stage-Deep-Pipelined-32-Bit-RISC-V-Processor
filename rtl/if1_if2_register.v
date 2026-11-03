`timescale 1ns/1ps
// Pipeline register IF1 -> IF2: PC of the instruction being fetched.
// Priority: reset > flush (becomes a bubble, valid = 0) > stall (hold) > load new values.
module if1_if2_register (
    input  wire clk,
    input  wire reset,   // synchronous, active high
    input  wire flush,   // turn the contents into a bubble
    input  wire stall,   // keep the current contents
    input  wire         in_valid,
    input  wire [31:0]  in_pc,
    output reg          out_valid,
    output reg  [31:0]  out_pc
);
    always @(posedge clk) begin
        if (reset || flush) begin
            out_valid <= 1'd0;
            out_pc <= 32'd0;
        end else if (!stall) begin
            out_valid <= in_valid;
            out_pc <= in_pc;
        end
    end
endmodule
