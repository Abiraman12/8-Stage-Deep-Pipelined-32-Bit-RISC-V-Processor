#!/usr/bin/env python3
"""Tiny RV32I assembler + reference ISS (golden model) for the 8-stage project.
Writes, for each test program in tests_src/*.s :
  tests/<name>.hex        256 instruction words (padded with NOP)
  tests/<name>_regs.hex   32 expected final register values
  tests/<name>_mem.hex    256 expected final data-memory words
  tests/<name>_pc.hex     expected retired-PC sequence (program order)
  tests/<name>_stats.hex  N retired, T redirects, S load-use stalls, cycles
The ISS is written from the RISC-V spec, NOT from the RTL, so it is an independent check.
"""
import re, sys, os, glob

M32 = 0xFFFFFFFF
IMEM_WORDS, DMEM_WORDS = 256, 256
NOP = 0x00000013

def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v

def reg(tok):
    m = re.fullmatch(r'x(\d+)', tok.strip())
    if not m or int(m.group(1)) > 31:
        raise ValueError("bad register " + tok)
    return int(m.group(1))

def num(tok):
    return int(tok.strip(), 0)

R_OPS = {'add': (0, 0), 'sub': (0, 0x20), 'sll': (1, 0), 'slt': (2, 0), 'sltu': (3, 0),
         'xor': (4, 0), 'srl': (5, 0), 'sra': (5, 0x20), 'or': (6, 0), 'and': (7, 0)}
I_OPS = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SH_OPS = {'slli': (1, 0), 'srli': (5, 0), 'srai': (5, 0x20)}
L_OPS = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
S_OPS = {'sb': 0, 'sh': 1, 'sw': 2}
B_OPS = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}

def enc_r(f7, rs2, rs1, f3, rd, op): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def enc_i(imm, rs1, f3, rd, op): return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def enc_s(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op
def enc_b(off, rs2, rs1, f3, op):
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | op
def enc_u(imm20, rd, op): return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op
def enc_j(off, rd, op):
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | \
           (((o >> 12) & 0xFF) << 12) | (rd << 7) | op

def parse_mem(tok):
    m = re.fullmatch(r'\s*(-?\w+)\((x\d+)\)\s*', tok)
    if not m: raise ValueError("bad mem operand " + tok)
    return num(m.group(1)), reg(m.group(2))

def assemble(text):
    lines, labels, pc = [], {}, 0
    for raw in text.splitlines():
        line = raw.split('#')[0].strip()
        if not line: continue
        while ':' in line:
            lab, line = line.split(':', 1)
            labels[lab.strip()] = pc
            line = line.strip()
        if not line: continue
        lines.append((pc, line)); pc += 4
    words = []
    for pc, line in lines:
        parts = line.split(None, 1)
        op = parts[0].lower()
        args = [a.strip() for a in parts[1].split(',')] if len(parts) > 1 else []
        if op == 'nop': w = NOP
        elif op == '.word': w = num(args[0]) & M32
        elif op in R_OPS:
            f3, f7 = R_OPS[op]; w = enc_r(f7, reg(args[2]), reg(args[1]), f3, reg(args[0]), 0x33)
        elif op in I_OPS: w = enc_i(num(args[2]), reg(args[1]), I_OPS[op], reg(args[0]), 0x13)
        elif op in SH_OPS:
            f3, f7 = SH_OPS[op]; w = enc_r(f7, num(args[2]) & 31, reg(args[1]), f3, reg(args[0]), 0x13)
        elif op in L_OPS:
            off, rb = parse_mem(args[1]); w = enc_i(off, rb, L_OPS[op], reg(args[0]), 0x03)
        elif op in S_OPS:
            off, rb = parse_mem(args[1]); w = enc_s(off, reg(args[0]), rb, S_OPS[op], 0x23)
        elif op in B_OPS:
            w = enc_b(labels[args[2]] - pc, reg(args[1]), reg(args[0]), B_OPS[op], 0x63)
        elif op == 'lui': w = enc_u(num(args[1]), reg(args[0]), 0x37)
        elif op == 'auipc': w = enc_u(num(args[1]), reg(args[0]), 0x17)
        elif op == 'jal': w = enc_j(labels[args[1]] - pc, reg(args[0]), 0x6F)
        elif op == 'jalr':
            if len(args) == 2: off, rb = parse_mem(args[1])
            else: rb, off = reg(args[1]), num(args[2])
            w = enc_i(off, rb, 0, reg(args[0]), 0x67)
        elif op == 'fence': w = 0x0FF0000F
        elif op == 'ecall': w = 0x00000073
        elif op == 'ebreak': w = 0x00100073
        else: raise ValueError("unknown op: " + line)
        words.append(w & M32)
    return words

# ---------------- reference ISS ----------------
def run_iss(words, max_steps=100000):
    imem = list(words) + [NOP] * (IMEM_WORDS - len(words))
    dmem = [0] * DMEM_WORDS
    x = [0] * 32
    pc, retired_pcs = 0, []
    taken, stalls = 0, 0
    prev_load_rd = None

    def uses(w):
        op = w & 0x7F
        u1 = op in (0x33, 0x13, 0x03, 0x23, 0x63, 0x67)
        u2 = op in (0x33, 0x23, 0x63)
        return u1, u2

    for _ in range(max_steps):
        w = imem[(pc >> 2) % IMEM_WORDS]
        op, rd, f3 = w & 0x7F, (w >> 7) & 31, (w >> 12) & 7
        rs1, rs2, f7 = (w >> 15) & 31, (w >> 20) & 31, w >> 25
        # load-use stall rule (consumer directly after a load)
        u1, u2 = uses(w)
        if prev_load_rd and ((u1 and rs1 == prev_load_rd) or (u2 and rs2 == prev_load_rd)):
            stalls += 1
        prev_load_rd = None
        a, b = x[rs1], x[rs2]
        npc, wr = pc + 4, None
        imm_i, imm_s = sx(w >> 20, 12), sx(((w >> 25) << 5) | ((w >> 7) & 31), 12)
        imm_b = sx((((w >> 31) & 1) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1), 13)
        imm_u = w & 0xFFFFF000
        imm_j = sx((((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12) | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1), 21)
        sa, sb = sx(a, 32), sx(b, 32)
        if op == 0x33:
            if f3 == 0: wr = (a - b) if f7 == 0x20 else (a + b)
            elif f3 == 1: wr = a << (b & 31)
            elif f3 == 2: wr = int(sa < sb)
            elif f3 == 3: wr = int(a < b)
            elif f3 == 4: wr = a ^ b
            elif f3 == 5: wr = (sa >> (b & 31)) if f7 == 0x20 else (a >> (b & 31))
            elif f3 == 6: wr = a | b
            else: wr = a & b
        elif op == 0x13:
            i = imm_i & M32; sh = (w >> 20) & 31
            if f3 == 0: wr = a + i
            elif f3 == 2: wr = int(sa < sx(i, 32))
            elif f3 == 3: wr = int(a < i)
            elif f3 == 4: wr = a ^ i
            elif f3 == 6: wr = a | i
            elif f3 == 7: wr = a & i
            elif f3 == 1: wr = a << sh
            else: wr = (sa >> sh) if f7 == 0x20 else (a >> sh)
        elif op == 0x03:
            addr = (a + imm_i) & M32
            word = dmem[(addr >> 2) % DMEM_WORDS]; sh = (addr & 3) * 8
            byte = (word >> sh) & 0xFF; half = (word >> (8 * (addr & 2))) & 0xFFFF
            wr = {0: sx(byte, 8), 1: sx(half, 16), 2: word, 4: byte, 5: half}[f3]
            prev_load_rd = rd if rd != 0 else None
        elif op == 0x23:
            addr = (a + imm_s) & M32; idx = (addr >> 2) % DMEM_WORDS; word = dmem[idx]
            if f3 == 0: m, v, sh = 0xFF, b & 0xFF, (addr & 3) * 8
            elif f3 == 1: m, v, sh = 0xFFFF, b & 0xFFFF, 8 * (addr & 2)
            else: m, v, sh = M32, b, 0
            dmem[idx] = (word & ~(m << sh) & M32) | ((v & m) << sh)
        elif op == 0x63:
            c = {0: a == b, 1: a != b, 4: sa < sb, 5: sa >= sb, 6: a < b, 7: a >= b}[f3]
            if c: npc = pc + imm_b; taken += 1
        elif op == 0x37: wr = imm_u
        elif op == 0x17: wr = pc + imm_u
        elif op == 0x6F: wr = pc + 4; npc = pc + imm_j; taken += 1
        elif op == 0x67: wr = pc + 4; npc = (a + imm_i) & ~1; taken += 1
        elif op == 0x0F: pass
        elif op == 0x73:
            retired_pcs.append(pc); break
        else:
            raise RuntimeError("illegal instruction %08x at pc %x" % (w, pc))
        retired_pcs.append(pc)
        if wr is not None and rd != 0: x[rd] = wr & M32
        pc = npc & M32
    else:
        raise RuntimeError("ISS did not halt")
    n = len(retired_pcs)
    cycles = n + 7 + stalls + 4 * taken      # 8-stage timing model (see docs)
    return x, dmem, retired_pcs, (n, taken, stalls, cycles), imem

def write_hex(path, vals, width=8):
    with open(path, 'w') as f:
        for v in vals: f.write(('%0' + str(width) + 'x\n') % (v & M32))

def selftest():
    # encodings checked against the official RISC-V spec / well-known assembler output
    known = {'addi x1,x0,5': 0x00500093, 'add x3,x1,x2': 0x002081B3, 'sub x4,x3,x1': 0x40118233,
             'sw x3,0(x0)': 0x00302023, 'lw x5,0(x0)': 0x00002283, 'lui x1,0x12345': 0x123450B7,
             'ecall': 0x00000073, 'ebreak': 0x00100073, 'jalr x0,0(x1)': 0x00008067,
             'srai x5,x6,3': 0x40335293, 'sltu x7,x8,x9': 0x009433B3}
    for src, want in known.items():
        got = assemble(src)[0]
        assert got == want, "%s: got %08x want %08x" % (src, got, want)
    # branch / jal encodings from the student's own 2-stage testbench: BEQ x4,x2,+8
    assert assemble("beq x4,x2,t\nnop\nt: nop")[0] == 0x00220463
    assert assemble("jal x1,t\nnop\nt: nop")[0] == 0x008000EF
    print("assembler self-test OK")

if __name__ == '__main__':
    selftest()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for src in sorted(glob.glob(os.path.join(root, 'tests_src', '*.s'))):
        name = os.path.splitext(os.path.basename(src))[0]
        words = assemble(open(src).read())
        assert len(words) <= IMEM_WORDS
        x, dm, pcs, stats, imem = run_iss(words)
        out = os.path.join(root, 'tests', name)
        write_hex(out + '.hex', imem)
        write_hex(out + '_regs.hex', x)
        write_hex(out + '_mem.hex', dm)
        write_hex(out + '_pc.hex', pcs)
        write_hex(out + '_stats.hex', list(stats))
        print("%-12s N=%3d T=%2d S=%2d cycles=%3d" % ((name,) + stats))
