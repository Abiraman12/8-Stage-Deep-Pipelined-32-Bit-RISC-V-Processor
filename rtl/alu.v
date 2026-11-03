`timescale 1ns/1ps
// EX stage: 32-bit ALU for all RV32I arithmetic, logic, shift and compare operations.
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_op,
    output reg  [31:0] result
);
    localparam ALU_ADD = 4'd0, ALU_SUB = 4'd1, ALU_SLL = 4'd2, ALU_SLT = 4'd3,
               ALU_SLTU = 4'd4, ALU_XOR = 4'd5, ALU_SRL = 4'd6, ALU_SRA = 4'd7,
               ALU_OR = 4'd8, ALU_AND = 4'd9, ALU_PASSB = 4'd10;

    wire [4:0]         shamt    = b[4:0];
    wire signed [31:0] a_signed = a;
    wire signed [31:0] b_signed = b;

    always @(*) begin
        case (alu_op)
            ALU_ADD:   result = a + b;
            ALU_SUB:   result = a - b;
            ALU_SLL:   result = a << shamt;
            ALU_SLT:   result = (a_signed < b_signed) ? 32'd1 : 32'd0;
            ALU_SLTU:  result = (a < b)               ? 32'd1 : 32'd0;
            ALU_XOR:   result = a ^ b;
            ALU_SRL:   result = a >> shamt;
            ALU_SRA:   result = a_signed >>> shamt;
            ALU_OR:    result = a | b;
            ALU_AND:   result = a & b;
            ALU_PASSB: result = b;
            default:   result = 32'd0;
        endcase
    end
endmodule
