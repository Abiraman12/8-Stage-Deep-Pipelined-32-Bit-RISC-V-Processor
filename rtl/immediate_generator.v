`timescale 1ns/1ps
// ID stage: builds the 32-bit sign-extended immediate for each instruction format.
module immediate_generator (
    input  wire [31:0] instr,
    input  wire [2:0]  fmt,
    output reg  [31:0] imm
);
    localparam FMT_R = 3'd0, FMT_I = 3'd1, FMT_S = 3'd2,
               FMT_B = 3'd3, FMT_U = 3'd4, FMT_J = 3'd5;

    always @(*) begin
        case (fmt)
            FMT_I:   imm = {{20{instr[31]}}, instr[31:20]};
            FMT_S:   imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            FMT_B:   imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            FMT_U:   imm = {instr[31:12], 12'b0};
            FMT_J:   imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default: imm = 32'd0;
        endcase
    end
endmodule
