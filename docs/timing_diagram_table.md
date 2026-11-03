Pipeline timing diagram (cycle-level model trace of `tests_src/demo_timing.s`; model, not an RTL waveform).
`RR RR` = load-use stall (instruction waits one cycle). Rows ending early with `*` were wrong-path and flushed.

| pc | instruction | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | `addi x1,x0,5` | IF1 | IF2 | ID | RR | EX | MEM1 | MEM2 | WB |  |  |  |  |  |  |  |  |  |  |  |  |
| 4 | `addi x2,x1,1` |  | IF1 | IF2 | ID | RR | EX | MEM1 | MEM2 | WB |  |  |  |  |  |  |  |  |  |  |  |
| 8 | `sw   x2,0(x0)` |  |  | IF1 | IF2 | ID | RR | EX | MEM1 | MEM2 | WB |  |  |  |  |  |  |  |  |  |  |
| 12 | `lw   x3,0(x0)` |  |  |  | IF1 | IF2 | ID | RR | EX | MEM1 | MEM2 | WB |  |  |  |  |  |  |  |  |  |
| 16 | `add  x4,x3,x1` |  |  |  |  | IF1 | IF2 | ID | RR | RR | EX | MEM1 | MEM2 | WB |  |  |  |  |  |  |  |
| 20 | `beq  x4,x4,L` |  |  |  |  |  | IF1 | IF2 | ID | ID | RR | EX | MEM1 | MEM2 | WB |  |  |  |  |  |  |
| 24 | `addi x5,x0,111` * |  |  |  |  |  |  | IF1 | IF2 | IF2 | ID | RR |  |  |  |  |  |  |  |  |  |
| 28 | `addi x6,x0,7` * |  |  |  |  |  |  |  | IF1 |  |  |  |  |  |  |  |  |  |  |  |  |
| 28 | `addi x6,x0,7` * |  |  |  |  |  |  |  |  | IF1 | IF2 | ID |  |  |  |  |  |  |  |  |  |
| 32 | `ecall` * |  |  |  |  |  |  |  |  |  | IF1 | IF2 |  |  |  |  |  |  |  |  |  |
| 36 | `(nop fetch after halt)` * |  |  |  |  |  |  |  |  |  |  | IF1 |  |  |  |  |  |  |  |  |  |
| 28 | `addi x6,x0,7` |  |  |  |  |  |  |  |  |  |  |  | IF1 | IF2 | ID | RR | EX | MEM1 | MEM2 | WB |  |
| 32 | `ecall` |  |  |  |  |  |  |  |  |  |  |  |  | IF1 | IF2 | ID | RR | EX | MEM1 | MEM2 | WB |
| 36 | `(nop fetch after halt)` * |  |  |  |  |  |  |  |  |  |  |  |  |  | IF1 | IF2 | ID | RR |  |  |  |
| 40 | `(nop fetch after halt)` * |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF1 | IF2 | ID |  |  |  |
| 44 | `(nop fetch after halt)` * |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF1 | IF2 |  |  |  |
| 48 | `(nop fetch after halt)` * |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | IF1 |  |  |  |

Model totals: N=8 retired, T=1 redirects, S=1 load-use stalls, 20 cycles
