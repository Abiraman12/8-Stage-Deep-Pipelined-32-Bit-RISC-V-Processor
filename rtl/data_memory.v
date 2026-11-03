`timescale 1ns/1ps
// MEM1/MEM2 memory: 256 x 32-bit words (1 KB), byte-write strobes,
// ONE-CYCLE READ LATENCY: the request is presented during MEM1 and the registered
// word appears on rdata during MEM2. Stores commit at the clock edge ending MEM1.
module data_memory (
    input  wire        clk,
    input  wire        req_re,
    input  wire        req_we,
    input  wire [31:0] addr,        // byte address (word index = addr[9:2])
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,       // byte lane enables
    output reg  [31:0] rdata        // registered response
);
    reg [31:0] mem [0:255];
    reg [31:0] word_tmp;
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;
        rdata = 32'd0;
    end

    always @(posedge clk) begin
        if (req_we) begin
            word_tmp = mem[addr[9:2]];
            if (wstrb[0]) word_tmp[7:0]   = wdata[7:0];
            if (wstrb[1]) word_tmp[15:8]  = wdata[15:8];
            if (wstrb[2]) word_tmp[23:16] = wdata[23:16];
            if (wstrb[3]) word_tmp[31:24] = wdata[31:24];
            mem[addr[9:2]] <= word_tmp;
        end
        if (req_re)
            rdata <= mem[addr[9:2]];
    end
endmodule
