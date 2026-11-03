`timescale 1ns/1ps
// IF1 stage: holds the address of the instruction being fetched and computes the next PC.
// Priority: redirect (branch/jump from EX) > stall/hold > sequential PC+4.
module program_counter #(
    parameter RESET_PC = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        reset,            // synchronous, active high
    input  wire        stall,            // hold the PC (load-use stall or halted)
    input  wire        redirect,         // branch / jump taken in EX
    input  wire [31:0] redirect_target,  // new PC from EX
    output reg  [31:0] pc,               // address being fetched in IF1
    output wire [31:0] pc_plus4,         // sequential address
    output wire [31:0] next_pc           // value the PC will take at the next clock
);
    assign pc_plus4 = pc + 32'd4;
    assign next_pc  = redirect ? redirect_target :
                      stall    ? pc              : pc_plus4;

    always @(posedge clk) begin
        if (reset) pc <= RESET_PC;
        else       pc <= next_pc;
    end
endmodule
