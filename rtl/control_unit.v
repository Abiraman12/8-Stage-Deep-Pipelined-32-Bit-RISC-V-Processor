`timescale 1ns/1ps
// ID stage: turns the decoded instruction class into datapath control signals.
// An illegal instruction becomes a harmless bubble (no register / memory write).
module control_unit (
    input  wire       is_lui, is_auipc, is_jal, is_jalr, is_branch,
    input  wire       is_load, is_store, is_op_imm, is_op,
    input  wire       is_system,
    input  wire [2:0] funct3,
    input  wire       funct7_5,        // instr[30]: SUB / SRA select
    input  wire       illegal,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        alu_src_a_pc,    // 1: ALU operand A = PC (AUIPC)
    output reg        alu_src_b_imm,   // 1: ALU operand B = immediate
    output reg  [3:0] alu_op,
    output wire       branch_o,
    output wire       jal_o,
    output wire       jalr_o,
    output wire       system_o
);
    // ALU operation codes (must match alu.v)
    localparam ALU_ADD = 4'd0, ALU_SUB = 4'd1, ALU_SLL = 4'd2, ALU_SLT = 4'd3,
               ALU_SLTU = 4'd4, ALU_XOR = 4'd5, ALU_SRL = 4'd6, ALU_SRA = 4'd7,
               ALU_OR = 4'd8, ALU_AND = 4'd9, ALU_PASSB = 4'd10;

    assign branch_o = is_branch & ~illegal;
    assign jal_o    = is_jal    & ~illegal;
    assign jalr_o   = is_jalr   & ~illegal;
    assign system_o = is_system & ~illegal;

    always @(*) begin
        reg_write     = 1'b0;
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        alu_src_a_pc  = 1'b0;
        alu_src_b_imm = 1'b0;
        alu_op        = ALU_ADD;

        if (!illegal) begin
            if (is_op | is_op_imm) begin
                reg_write     = 1'b1;
                alu_src_b_imm = is_op_imm;
                case (funct3)
                    3'b000:  alu_op = (is_op & funct7_5) ? ALU_SUB : ALU_ADD;
                    3'b001:  alu_op = ALU_SLL;
                    3'b010:  alu_op = ALU_SLT;
                    3'b011:  alu_op = ALU_SLTU;
                    3'b100:  alu_op = ALU_XOR;
                    3'b101:  alu_op = funct7_5 ? ALU_SRA : ALU_SRL;
                    3'b110:  alu_op = ALU_OR;
                    3'b111:  alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end
            else if (is_load) begin
                reg_write = 1'b1; mem_read = 1'b1; alu_src_b_imm = 1'b1; alu_op = ALU_ADD;
            end
            else if (is_store) begin
                mem_write = 1'b1; alu_src_b_imm = 1'b1; alu_op = ALU_ADD;
            end
            else if (is_lui) begin
                reg_write = 1'b1; alu_src_b_imm = 1'b1; alu_op = ALU_PASSB;
            end
            else if (is_auipc) begin
                reg_write = 1'b1; alu_src_a_pc = 1'b1; alu_src_b_imm = 1'b1; alu_op = ALU_ADD;
            end
            else if (is_jal | is_jalr) begin
                reg_write = 1'b1;          // writes the link address PC+4
            end
            // branches, FENCE (NOP) and ECALL/EBREAK need no datapath control
        end
    end
endmodule
