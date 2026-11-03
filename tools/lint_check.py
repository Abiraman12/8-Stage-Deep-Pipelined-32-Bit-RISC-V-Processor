#!/usr/bin/env python3
"""Crude structural lint for the RTL (NOT a compiler): undeclared names, instance ports, widths."""
import re, glob, os, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
KW = set("""module endmodule input output inout wire reg integer parameter localparam assign always initial begin end
if else case endcase default posedge negedge or and not signed for while genvar generate endgenerate
function endfunction task endtask""".split())

def strip(t):
    t = re.sub(r'//.*', '', t); t = re.sub(r'/\*.*?\*/', '', t, flags=re.S)
    return re.sub(r'`timescale.*', '', t)

def width(rng):
    if not rng: return 1
    m = re.fullmatch(r'\[\s*(\d+)\s*:\s*(\d+)\s*\]', rng.strip())
    return abs(int(m.group(1)) - int(m.group(2))) + 1 if m else None

mods = {}
for f in sorted(glob.glob(root + '/rtl/*.v')):
    src = strip(open(f).read())
    for m in re.finditer(r'\bmodule\s+(\w+)\s*(#\s*\(.*?\))?\s*\((.*?)\)\s*;(.*?)\bendmodule', src, flags=re.S):
        name, params, ports, body = m.group(1), m.group(2) or '', m.group(3), m.group(4)
        decl, pw, pdir = {}, {}, {}
        for pm in re.finditer(r'\b(input|output)\s+(?:wire|reg)?\s*(?:signed)?\s*(\[[^\]]+\])?\s*(.*?)(?=\binput\b|\boutput\b|$)', ports, flags=re.S):
            d, rng, names = pm.groups()
            for n in re.findall(r'\b([A-Za-z_]\w*)\b', names):
                decl[n] = width(rng); pw[n] = width(rng); pdir[n] = d
        for pn in re.findall(r'\b(?:parameter|localparam)\s+(?:\[[^\]]+\]\s*)?(\w+)', params + body): decl[pn] = 0
        for dm in re.finditer(r'\b(wire|reg|integer)\s*(?:signed)?\s*(\[[^\]]+\])?\s*([^;]+);', body):
            kind, rng, names = dm.groups()
            for part in re.split(r',', re.sub(r'=.*?(?=,\s*\w+\s*(?:=|,|$))|=[^,]*$', '', names)):
                nm = re.match(r'\s*(\w+)', part)
                if nm: decl[nm.group(1)] = width(rng) if kind != 'integer' else 32
        for lm in re.finditer(r'\blocalparam\s+([^;]+);', body):
            for nm in re.findall(r'(\w+)\s*=', lm.group(1)): decl[nm] = 0
        mods[name] = dict(file=os.path.basename(f), decl=decl, pw=pw, pdir=pdir, body=body, ports=ports)

errors = 0
def err(*a):
    global errors; errors += 1; print('ERROR:', *a)

for name, M in mods.items():
    body = M['body']
    # instances
    inst_names = set()
    for im in re.finditer(r'\b(\w+)\s*(?:#\s*\((?:[^()]|\([^()]*\))*\))?\s*(\w+)\s*\(\s*(\.[^;]*?)\)\s*;', body, flags=re.S):
        mod, inst, conns = im.groups()
        if mod in KW or mod not in mods:
            if mod not in KW: err(name, 'instance of unknown module', mod)
            continue
        inst_names.add(inst)
        T = mods[mod]
        seen = {}
        for cm in re.finditer(r'\.(\w+)\s*\(((?:[^()]|\([^()]*\))*)\)', conns):
            p, e = cm.group(1), cm.group(2).strip()
            if p not in T['pw'] and p not in T['decl']:
                err(name, inst, 'no such port', p, 'on', mod); continue
            if p in seen: err(name, inst, 'port connected twice', p)
            seen[p] = e
            pwid = T['pw'].get(p)
            if re.fullmatch(r'\w+', e) and e in M['decl'] and pwid and M['decl'][e] and pwid != M['decl'][e]:
                err(name, inst, 'width mismatch port', p, pwid, 'vs signal', e, M['decl'][e])
            m2 = re.fullmatch(r"(\d+)'[bBdDhH]\w+", e)
            if m2 and pwid and int(m2.group(1)) != pwid: err(name, inst, 'const width', p, e, pwid)
        for p, d in T['pdir'].items():
            if p not in seen: err(name, inst, 'UNCONNECTED port', p, '(%s)' % d)
    # identifiers
    b = re.sub(r'\.\w+\s*\(', '(', body)
    b = re.sub(r"\d*'[sS]?[bBdDhHoO][0-9a-fA-F_xXzZ]+", ' ', b)
    b = re.sub(r'\$\w+|"[^"]*"', ' ', b)
    for im in re.finditer(r'\b(\w+)\s*(?:#\s*\((?:[^()]|\([^()]*\))*\))?\s*(\w+)\s*\(\s*\(', b): pass
    for tok in set(re.findall(r'\b[A-Za-z_]\w*\b', b)):
        if tok in KW or tok in M['decl'] or tok in mods or tok in inst_names: continue
        if tok in M['pw']: continue
        err(name, 'undeclared identifier:', tok)
    # driver count on ports of instances not checked; check outputs of module are driven somewhere
    for p, d in M['pdir'].items():
        if d == 'output' and not re.search(r'\b%s\b\s*(<=|=|\[)|assign\s+%s\b|\.\w+\s*\(\s*%s\s*\)' % (p, p, p), body):
            err(name, 'output never driven:', p)
print('modules checked:', len(mods), ' errors:', errors)
sys.exit(1 if errors else 0)
