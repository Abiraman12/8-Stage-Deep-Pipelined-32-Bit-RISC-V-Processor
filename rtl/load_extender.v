`timescale 1ns/1ps
// MEM2 stage: picks the addressed byte / halfword out of the returned word and
// sign- or zero-extends it. funct3: 000 LB, 001 LH, 010 LW, 100 LBU, 101 LHU.
module load_extender (
    input  wire [31:0] raw_word,
    input  wire [1:0]  addr_lo,
    input  wire [2:0]  funct3,
    output reg  [31:0] load_data
);
    reg [7:0]  b;
    reg [15:0] h;

    always @(*) begin
        case (addr_lo)
            2'd0:    b = raw_word[7:0];
            2'd1:    b = raw_word[15:8];
            2'd2:    b = raw_word[23:16];
            default: b = raw_word[31:24];
        endcase
        h = addr_lo[1] ? raw_word[31:16] : raw_word[15:0];

        case (funct3)
            3'b000:  load_data = {{24{b[7]}},  b};
            3'b001:  load_data = {{16{h[15]}}, h};
            3'b010:  load_data = raw_word;
            3'b100:  load_data = {24'd0, b};
            3'b101:  load_data = {16'd0, h};
            default: load_data = raw_word;
        endcase
    end
endmodule
