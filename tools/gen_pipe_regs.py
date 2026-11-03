#!/usr/bin/env python3
"""Generates the 7 pipeline-register modules from one field table (keeps ports consistent)."""
import os
V, PC, INSTR = ('valid', 1), ('pc', 32), ('instr', 32)
CTRL_ID = [('rs1_addr', 5), ('rs2_addr', 5), ('rd_addr', 5), ('imm', 32), ('funct3', 3),
           ('uses_rs1', 1), ('uses_rs2', 1), ('reg_write', 1), ('mem_read', 1), ('mem_write', 1),
           ('alu_src_a_pc', 1), ('alu_src_b_imm', 1), ('alu_op', 4),
           ('is_branch', 1), ('is_jal', 1), ('is_jalr', 1), ('is_system', 1), ('illegal', 1)]
REGS = [
 ('if1_if2_register', 'IF1 -> IF2: PC of the instruction being fetched', [V, PC]),
 ('if2_id_register',  'IF2 -> ID: fetched instruction with its PC', [V, PC, INSTR]),
 ('id_rr_register',   'ID -> RR: decoded fields, immediate and control signals', [V, PC, INSTR] + CTRL_ID),
 ('rr_ex_register',   'RR -> EX: as ID_RR plus the two register operands', [V, PC, INSTR] + CTRL_ID + [('rs1_data', 32), ('rs2_data', 32)]),
 ('ex_mem1_register', 'EX -> MEM1: ALU result / link address, store data, memory + write-back control',
    [V, PC, INSTR, ('rd_addr', 5), ('funct3', 3), ('reg_write', 1), ('mem_read', 1), ('mem_write', 1),
     ('alu_result', 32), ('store_data', 32)]),
 ('mem1_mem2_register', 'MEM1 -> MEM2: address / result and load control (data memory response is registered inside data_memory)',
    [V, PC, INSTR, ('rd_addr', 5), ('funct3', 3), ('reg_write', 1), ('mem_read', 1), ('alu_result', 32)]),
 ('mem2_wb_register', 'MEM2 -> WB: ALU result, extended load data and write-back control',
    [V, PC, INSTR, ('rd_addr', 5), ('reg_write', 1), ('mem_to_reg', 1), ('alu_result', 32), ('load_data', 32)]),
]
def rng(w): return '' if w == 1 else '[%d:0] ' % (w - 1)
def dflt(n, w): return "32'h0000_0013" if n == 'instr' else "%d'd0" % w
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'rtl')
for name, desc, fields in REGS:
    L = ['`timescale 1ns/1ps', '// Pipeline register ' + desc + '.',
         '// Priority: reset > flush (becomes a bubble, valid = 0) > stall (hold) > load new values.',
         'module %s (' % name, '    input  wire clk,', '    input  wire reset,   // synchronous, active high',
         '    input  wire flush,   // turn the contents into a bubble',
         '    input  wire stall,   // keep the current contents']
    for n, w in fields: L.append('    input  wire %s%s,' % (rng(w).ljust(8) if w > 1 else ' ' * 8, 'in_' + n))
    for i, (n, w) in enumerate(fields):
        L.append('    output reg  %s%s%s' % (rng(w).ljust(8) if w > 1 else ' ' * 8, 'out_' + n, ',' if i < len(fields) - 1 else ''))
    L += [');', '    always @(posedge clk) begin', '        if (reset || flush) begin']
    for n, w in fields: L.append('            out_%s <= %s;' % (n, dflt(n, w)))
    L += ['        end else if (!stall) begin']
    for n, w in fields: L.append('            out_%s <= in_%s;' % (n, n))
    L += ['        end', '    end', 'endmodule', '']
    open(os.path.join(root, name + '.v'), 'w').write('\n'.join(L))
    print('wrote', name + '.v', len(fields), 'fields')
