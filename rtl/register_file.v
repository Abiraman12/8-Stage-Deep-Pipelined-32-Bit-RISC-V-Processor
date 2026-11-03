`timescale 1ns/1ps
// RR stage (read) + WB stage (write): 32 x 32-bit registers, 2 read ports, 1 write port.
// x0 always reads zero and can never be written.
// Write-through bypass: a read in the same cycle as a write to the same register
// returns the new value (covers the instruction that is 4 ahead, see docs).
module register_file (
    input  wire        clk,
    input  wire        reset,
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,
    input  wire [4:0]  raddr1,
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);
    reg [31:0] regs [0:31];
    integer i;

    wire wr_en = we & (waddr != 5'd0);

    initial begin
        for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;
    end

    assign rdata1 = (raddr1 == 5'd0)           ? 32'd0 :
                    (wr_en && waddr == raddr1) ? wdata :
                                                 regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0)           ? 32'd0 :
                    (wr_en && waddr == raddr2) ? wdata :
                                                 regs[raddr2];

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 32'd0;
        end else if (wr_en) begin
            regs[waddr] <= wdata;
        end
    end
endmodule
