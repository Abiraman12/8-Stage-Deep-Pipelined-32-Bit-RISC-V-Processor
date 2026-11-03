`timescale 1ns/1ps
// IF2 stage memory: 256 x 32-bit words (1 KB), word aligned, asynchronous read.
// The IF1_IF2 register holds the address stable for the whole IF2 cycle, so the
// instruction is captured by the IF2_ID register at the end of that cycle.
// Optional preload: parameter INIT_FILE = "tests/xxx.hex" ($readmemh format).
module instruction_memory #(
    parameter INIT_FILE = ""
) (
    input  wire [31:0] addr,    // byte address
    output wire [31:0] instr
);
    reg [31:0] mem [0:255];
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 32'h0000_0013;           // NOP = addi x0,x0,0
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    assign instr = mem[addr[9:2]];            // addresses wrap every 1 KB
endmodule
