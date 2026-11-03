#!/usr/bin/env python3
"""Cycle-level Python model of the 8-stage microarchitecture (same stage boundaries, forwarding
priority, stall and flush rules as the RTL). Used to check the DESIGN LOGIC against the
independent ISS. It does not execute the Verilog."""
import sys, glob, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rvasm import assemble, run_iss, sx, M32, NOP

def bubble(): return dict(valid=0, pc=0, instr=NOP, rd=0, rs1=0, rs2=0, uses1=0, uses2=0, rw=0, mr=0, mw=0,
                          f3=0, imm=0, srcpc=0, srcimm=0, op='add', br=0, jal=0, jalr=0, sysc=0, a=0, b=0,
                          res=0, sd=0, load=0, m2r=0)

def decode(instr, pc, valid, uid=None):
    d = bubble(); d.update(valid=valid, pc=pc, instr=instr, uid=uid)
    op = instr & 0x7F; f3 = (instr >> 12) & 7; f7 = instr >> 25
    d.update(rd=(instr >> 7) & 31, rs1=(instr >> 15) & 31, rs2=(instr >> 20) & 31, f3=f3)
    imm_i = sx(instr >> 20, 12) & M32
    imm_s = sx(((instr >> 25) << 5) | ((instr >> 7) & 31), 12) & M32
    imm_b = sx((((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11) | (((instr >> 25) & 63) << 5) | (((instr >> 8) & 15) << 1), 13) & M32
    imm_j = sx((((instr >> 31) & 1) << 20) | (((instr >> 12) & 255) << 12) | (((instr >> 20) & 1) << 11) | (((instr >> 21) & 1023) << 1), 21) & M32
    alu = {0: 'sub' if f7 == 0x20 else 'add', 1: 'sll', 2: 'slt', 3: 'sltu', 4: 'xor', 5: 'sra' if f7 == 0x20 else 'srl', 6: 'or', 7: 'and'}
    if op == 0x33: d.update(uses1=1, uses2=1, rw=1, op=alu[f3])
    elif op == 0x13: d.update(uses1=1, rw=1, srcimm=1, imm=imm_i, op=('add' if f3 == 0 else alu[f3]))
    elif op == 0x03: d.update(uses1=1, rw=1, mr=1, srcimm=1, imm=imm_i)
    elif op == 0x23: d.update(uses1=1, uses2=1, mw=1, srcimm=1, imm=imm_s)
    elif op == 0x63: d.update(uses1=1, uses2=1, br=1, imm=imm_b)
    elif op == 0x37: d.update(rw=1, srcimm=1, imm=instr & 0xFFFFF000, op='passb')
    elif op == 0x17: d.update(rw=1, srcpc=1, srcimm=1, imm=instr & 0xFFFFF000)
    elif op == 0x6F: d.update(rw=1, jal=1, imm=imm_j)
    elif op == 0x67: d.update(uses1=1, rw=1, jalr=1, imm=imm_i)
    elif op == 0x73: d.update(sysc=1)
    return d

def alu(op, a, b):
    sa, sb, sh = sx(a, 32), sx(b, 32), b & 31
    return M32 & {'add': a + b, 'sub': a - b, 'sll': a << sh, 'slt': int(sa < sb), 'sltu': int(a < b),
                  'xor': a ^ b, 'srl': a >> sh, 'sra': sa >> sh, 'or': a | b, 'and': a & b, 'passb': b}[op]

def load_ext(raw, lo, f3):
    byte = (raw >> (8 * lo)) & 0xFF; half = (raw >> (16 * (lo >> 1))) & 0xFFFF
    return M32 & {0: sx(byte, 8), 1: sx(half, 16), 2: raw, 4: byte, 5: half}.get(f3, raw)

def run(words, max_cycles=5000, trace=None):
    imem = list(words) + [NOP] * (256 - len(words)); dmem = [0] * 256; rdata = 0
    x = [0] * 32; pc = 0; halted = 0
    f12 = dict(valid=0, pc=0); f2d = dict(valid=0, pc=0, instr=NOP)
    d2r, r2e, e2m, m12, m2w = bubble(), bubble(), bubble(), bubble(), bubble()
    cyc = stalls = redirects = 0; retired = []; done = False; extra = 0
    for _ in range(max_cycles):
        if trace is not None:
            trace.append([None if halted else (cyc, pc)] + [(st.get('uid'), st['pc']) if st['valid'] else None for st in (f12, f2d, d2r, r2e, e2m, m12, m2w)])
        # ---- WB
        wb_data = m2w['load'] if m2w['m2r'] else m2w['res']
        wb_we = m2w['valid'] and m2w['rw'] and m2w['rd'] != 0
        if m2w['valid']: retired.append(m2w['pc'])
        halt_ret = m2w['valid'] and m2w['instr'] in (0x73, 0x100073)
        # ---- MEM2
        load_data = load_ext(rdata, m12['res'] & 3, m12['f3'])
        mem2_res = load_data if m12['mr'] else m12['res']
        # ---- EX (forwarding, priority MEM1 > MEM2 > WB)
        def fwd(rs, uses, rdata_):
            if not uses: return rdata_
            if e2m['valid'] and e2m['rw'] and not e2m['mr'] and e2m['rd'] != 0 and e2m['rd'] == rs: return e2m['res']
            if m12['valid'] and m12['rw'] and m12['rd'] != 0 and m12['rd'] == rs: return mem2_res
            if m2w['valid'] and m2w['rw'] and m2w['rd'] != 0 and m2w['rd'] == rs: return wb_data
            return rdata_
        # safety: the forbidden case (consumer in EX, load in MEM1) must never happen
        if r2e['valid'] and e2m['valid'] and e2m['mr'] and e2m['rd'] != 0 and \
           ((r2e['uses1'] and r2e['rs1'] == e2m['rd']) or (r2e['uses2'] and r2e['rs2'] == e2m['rd'])):
            raise RuntimeError("consumer in EX while its load is in MEM1 (hazard unit failed)")
        a = fwd(r2e['rs1'], r2e['uses1'], r2e['a']); b = fwd(r2e['rs2'], r2e['uses2'], r2e['b'])
        ra = r2e['pc'] if r2e['srcpc'] else a; rb = r2e['imm'] if r2e['srcimm'] else b
        res = alu(r2e['op'], ra, rb)
        if r2e['jal'] or r2e['jalr']: res = (r2e['pc'] + 4) & M32
        sa, sb = sx(a, 32), sx(b, 32); f3 = r2e['f3']
        cond = {0: a == b, 1: a != b, 4: sa < sb, 5: sa >= sb, 6: a < b, 7: a >= b}.get(f3, False)
        v = r2e['valid']
        redirect = bool(v and ((r2e['br'] and cond) or r2e['jal'] or r2e['jalr']))
        target = ((a + r2e['imm']) & M32 & ~1) if r2e['jalr'] else (r2e['pc'] + r2e['imm']) & M32
        halt_req = bool(v and r2e['sysc'])
        # ---- hazard: instruction in RR needs a load that is in EX
        lus = bool(d2r['valid'] and r2e['valid'] and r2e['mr'] and r2e['rd'] != 0 and
                   ((d2r['uses1'] and d2r['rs1'] == r2e['rd']) or (d2r['uses2'] and d2r['rs2'] == r2e['rd'])))
        if redirect and lus: raise RuntimeError("stall and redirect overlap")
        # ---- RR (regfile read with write bypass)
        def rf(r):
            if r == 0: return 0
            return wb_data if (wb_we and m2w['rd'] == r) else x[r]
        rr_a, rr_b = rf(d2r['rs1']), rf(d2r['rs2'])
        # ---- ID / IF2
        dec = decode(f2d['instr'], f2d['pc'], f2d['valid'], f2d.get('uid'))
        if2_instr = imem[(f12['pc'] >> 2) % 256]
        # ---- MEM1 request
        m1_re = e2m['valid'] and e2m['mr']; m1_we = e2m['valid'] and e2m['mw']
        idx = (e2m['res'] >> 2) % 256; lo = e2m['res'] & 3
        # =============== clock edge: compute next state ===============
        flush_young = redirect or halt_req or halted
        flush_rrex = flush_young or lus
        n_halted = 1 if halt_req else halted
        n_pc = target if redirect else (pc if (lus or halted or halt_req) else (pc + 4) & M32)
        if m1_we:
            w = dmem[idx]
            if e2m['f3'] == 0: sh, m, val = 8 * lo, 0xFF, e2m['sd'] & 0xFF
            elif e2m['f3'] == 1: sh, m, val = 8 * (lo & 2), 0xFFFF, e2m['sd'] & 0xFFFF
            else: sh, m, val = 0, M32, e2m['sd']
            dmem[idx] = (w & ~(m << sh) & M32) | (val << sh)
        n_rdata = dmem_old = None
        n_rdata = rdata
        if m1_re: n_rdata = dmem[idx]                  # no same-cycle write: re and we never coincide
        if wb_we: x[m2w['rd']] = wb_data
        # pipeline registers
        n_m2w = dict(m12); n_m2w.update(m2r=m12['mr'], load=load_data)
        n_m12 = dict(e2m)
        n_e2m = dict(r2e); n_e2m.update(res=res, sd=b)
        if flush_rrex: n_r2e = bubble()
        else:
            n_r2e = dict(d2r); n_r2e.update(a=rr_a, b=rr_b)
        if flush_young: n_d2r, n_f2d, n_f12 = bubble(), dict(valid=0, pc=0, instr=NOP), dict(valid=0, pc=0)
        elif lus: n_d2r, n_f2d, n_f12 = d2r, f2d, f12
        else:
            n_d2r = dec; n_f2d = dict(valid=f12['valid'], pc=f12['pc'], instr=if2_instr, uid=f12.get('uid')); n_f12 = dict(valid=1, pc=pc, uid=cyc)
        # counters
        cyc += 1
        if lus: stalls += 1
        if redirect: redirects += 1
        if halt_ret: done = True; break
        pc, halted, rdata = n_pc, n_halted, n_rdata
        m2w, m12, e2m, r2e, d2r, f2d, f12 = n_m2w, n_m12, n_e2m, n_r2e, n_d2r, n_f2d, n_f12
    assert done, "model did not halt"
    return x, dmem, retired, (len(retired), redirects, stalls, cyc)

if __name__ == '__main__':
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    bad = 0
    for src in sorted(glob.glob(root + '/tests_src/*.s')):
        name = os.path.basename(src)[:-2]
        words = assemble(open(src).read())
        gx, gm, gp, gs, _ = run_iss(words)
        mx, mm, mp, ms = run(words)
        ok = (gx == mx and gm == mm and gp == mp and gs == ms)
        bad += not ok
        print("%-13s %s  model: N=%d T=%d S=%d cycles=%d   ISS-predicted cycles=%d" % (name, "MATCH" if ok else "MISMATCH", *ms, gs[3]))
        if not ok:
            if gx != mx: print("   regs differ:", [(i, hex(a), hex(b)) for i, (a, b) in enumerate(zip(gx, mx)) if a != b])
            if gm != mm: print("   mem differs:", [(i, hex(a), hex(b)) for i, (a, b) in enumerate(zip(gm, mm)) if a != b][:6])
            if gp != mp: print("   retire order differs at", next(i for i, (a, b) in enumerate(zip(gp, mp)) if a != b) if len(gp) == len(mp) else "length")
            if gs != ms: print("   stats ISS", gs, "model", ms)
    sys.exit(1 if bad else 0)
