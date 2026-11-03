`timescale 1ns/1ps
// ID stage: splits the instruction into fields, identifies the class/format and
// detects illegal encodings. Pure combinational logic.
module instruction_decoder (
    input  wire [31:0] instr,
    output wire [6:0]  opcode,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [6:0]  funct7,
    output wire        is_lui,
    output wire        is_auipc,
    output wire        is_jal,
    output wire        is_jalr,
    output wire        is_branch,
    output wire        is_load,
    output wire        is_store,
    output wire        is_op_imm,
    output wire        is_op,
    output wire        is_fence,
    output wire        is_system,      // ECALL / EBREAK only
    output wire        uses_rs1,       // instruction really reads rs1
    output wire        uses_rs2,       // instruction really reads rs2
    output reg  [2:0]  fmt,            // instruction format (see localparams)
    output reg         illegal
);
    localparam FMT_R = 3'd0, FMT_I = 3'd1, FMT_S = 3'd2,
               FMT_B = 3'd3, FMT_U = 3'd4, FMT_J = 3'd5;

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    wire std_len = (instr[1:0] == 2'b11);   // 32-bit instruction (no compressed ISA)

    assign is_lui    = std_len & (opcode[6:2] == 5'b01101);
    assign is_auipc  = std_len & (opcode[6:2] == 5'b00101);
    assign is_jal    = std_len & (opcode[6:2] == 5'b11011);
    assign is_jalr   = std_len & (opcode[6:2] == 5'b11001);
    assign is_branch = std_len & (opcode[6:2] == 5'b11000);
    assign is_load   = std_len & (opcode[6:2] == 5'b00000);
    assign is_store  = std_len & (opcode[6:2] == 5'b01000);
    assign is_op_imm = std_len & (opcode[6:2] == 5'b00100);
    assign is_op     = std_len & (opcode[6:2] == 5'b01100);
    assign is_fence  = std_len & (opcode[6:2] == 5'b00011);
    assign is_system = std_len & (opcode[6:2] == 5'b11100) &
                       ((instr == 32'h0000_0073) | (instr == 32'h0010_0073));

    assign uses_rs1 = is_op | is_op_imm | is_load | is_store | is_branch | is_jalr;
    assign uses_rs2 = is_op | is_store | is_branch;

    // Format identification
    always @(*) begin
        fmt = FMT_I;
        if (is_op)                      fmt = FMT_R;
        else if (is_store)              fmt = FMT_S;
        else if (is_branch)             fmt = FMT_B;
        else if (is_lui | is_auipc)     fmt = FMT_U;
        else if (is_jal)                fmt = FMT_J;
        else                            fmt = FMT_I;
    end

    // Illegal instruction detection (unsupported opcode or bad funct3/funct7)
    always @(*) begin
        illegal = 1'b1;
        if (is_lui | is_auipc | is_jal)
            illegal = 1'b0;
        else if (is_jalr)
            illegal = (funct3 != 3'b000);
        else if (is_branch)
            illegal = (funct3 == 3'b010) | (funct3 == 3'b011);
        else if (is_load)
            illegal = ~((funct3 == 3'b000) | (funct3 == 3'b001) | (funct3 == 3'b010) |
                        (funct3 == 3'b100) | (funct3 == 3'b101));
        else if (is_store)
            illegal = ~((funct3 == 3'b000) | (funct3 == 3'b001) | (funct3 == 3'b010));
        else if (is_op_imm) begin
            if (funct3 == 3'b001)
                illegal = (funct7 != 7'b0000000);
            else if (funct3 == 3'b101)
                illegal = ~((funct7 == 7'b0000000) | (funct7 == 7'b0100000));
            else
                illegal = 1'b0;
        end
        else if (is_op) begin
            if (funct7 == 7'b0000000)
                illegal = 1'b0;
            else if (funct7 == 7'b0100000)
                illegal = ~((funct3 == 3'b000) | (funct3 == 3'b101));
            else
                illegal = 1'b1;
        end
        else if (is_fence)
            illegal = (funct3 != 3'b000);
        else if (is_system)
            illegal = 1'b0;
        else
            illegal = 1'b1;
    end
endmodule
