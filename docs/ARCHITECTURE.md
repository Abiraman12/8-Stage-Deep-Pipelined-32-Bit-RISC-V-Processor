# Architecture and Analysis

## 1. Problems found in the 2-stage design (riscv_2stage.v)
- Decode, register read, ALU, memory and write-back are one stage: the stage's logic depth (memory read ->
  write data -> register write) is the longest path; it cannot be split to raise clock rate.
- No pipeline registers after the first stage, no valid bits, so no bubbles/stalls are possible.
- Only 8 instructions; funct3/funct7 checks incomplete (no shifts, XOR, SLT, LUI, JAL, JALR, byte/half loads).
- `data_mem[...]` is read combinationally inside the decode `always @(*)` block and written with a hierarchy
  that is not a separate module (no clear memory interface, cannot model latency).
- Branch target and compare are in the same stage as everything else; wrong-path flush is a single NOP only.
- No x0 protection on forwarded data (no forwarding at all), no illegal-instruction detection.
- It "works" without a hazard unit only because writeback happens in the stage that precedes the next decode.
Preserved ideas: separate instruction/data memories, x0 read as zero, BEQ offset encoding, NOP = ADDI x0,x0,0,
flush-on-taken-branch, testbench style (encoded programs, pass/fail).

## 2. Block diagram
```
       redirect/target (from EX)        stall (load-use) / halt
              |                                |
 +-----+   +-----------+  +----------+  +-----------+  +----------+  +----------+  +----------+
 | IF1 |-->|  IF1_IF2  |->| IF2      |->|  IF2_ID   |->| ID       |->|  ID_RR   |->| RR       |
 | PC  |   | valid,pc  |  | instr    |  |valid,pc,  |  | decoder  |  | fields,  |  | regfile  |
 |+4/mux|  +-----------+  | memory   |  | instr     |  | control  |  | imm,ctrl |  | 2 reads  |
 +-----+                  +----------+  +-----------+  | immgen   |  +----------+  +----+-----+
                                                       +----------+                     |
   +--------------------------------------------------------------------------------+   |
   v                                                                                    |
 +-----------+  +--------------------------------+  +-----------+  +-----------------+  |
 |  RR_EX    |->| EX: fwd mux, ALU, branch_ctrl  |->| EX_MEM1   |->| MEM1: dmem req, |  |
 | +rs1/rs2  |  | JAL/JALR link, target, halt    |  | result,   |  | store-data prep |  |
 +-----------+  +---------^----------------------+  | store data|  +--------+--------+  |
                 forwarding_unit  <-- MEM1/MEM2/WB  +-----------+           v           |
                 hazard_detection_unit (RR vs EX load)          +-----------+  +-----------------+
                                                                | MEM1_MEM2 |->| MEM2: registered|
                                                                +-----------+  | response, load  |
                                                                               | extender        |
   regfile write port  <-- WB: select ALU / load data  <--  MEM2_WB  <--------+-----------------+
```
## 3. The seven boundaries
| Register | Carries |
|---|---|
| IF1_IF2 | valid, pc |
| IF2_ID | valid, pc, instruction |
| ID_RR | + rs1/rs2/rd, imm, funct3, uses_rs1/2, ALU/mem/WB/branch controls, illegal |
| RR_EX | ID_RR fields + rs1_data, rs2_data |
| EX_MEM1 | valid, pc, instr, rd, funct3, reg_write, mem_read/write, result (or PC+4 link), store data |
| MEM1_MEM2 | valid, pc, instr, rd, funct3, reg_write, mem_read, address/result |
| MEM2_WB | valid, pc, instr, rd, reg_write, mem_to_reg, ALU result, extended load data |
Priority in every register: reset > flush (bubble, valid=0) > stall (hold) > load.

## 4. Hazard rules (all implemented as written)
- **Forwarding into EX**: MEM1 (ALU result) > MEM2 (ALU result or load data) > WB; x0 never forwarded;
  regfile write-through bypass covers the instruction 4 ahead. Coverage by distance d: d=1 MEM1, d=2 MEM2, d=3 WB, d>=4 regfile.
- **Load-use**: load in EX and consumer in RR -> hold PC/IF1_IF2/IF2_ID/ID_RR one cycle, bubble into RR_EX.
  Load at distance 2 needs no stall (data forwarded from MEM2). Penalty: 1 cycle. Conservative for store data (rs2).
- **Control**: predict-not-taken, resolve in EX. Flush RR, ID, IF2 and the IF1 slot = **4-cycle penalty**
  for taken branch, JAL and JALR.
- **Structural**: separate I/D memories, one request per cycle, data memory latency fixed at 1 cycle
  (request in MEM1, registered data visible in MEM2).
- Cycle formula checked by model: `cycles = N + 7 + S + 4*T` (fill = 7 extra cycles).

## 5. Documented simplifications
ECALL/EBREAK = halt (younger instructions flushed, fetch stops); FENCE = NOP; CSR/FENCE.I/compressed = illegal,
executed as a bubble and flagged by `dbg_illegal_ex` (no trap); misaligned loads/stores unsupported (aligned
assumed); 1 KB memories (addresses wrap); synchronous active-high reset. "Full RV32I" is claimed only
**after** your ModelSim run shows all tests passing; the tests cover every instruction except that no test
executes an illegal-encoding trap (none exists).

## 6. Pipeline timing diagram (model trace)
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

## 7. Performance comparison (ANALYTICAL MODEL, not measured)
Same 7 programs, cycles until the last instruction retires. Penalty rules: 8-stage = N+7+S+4T (checked by
the model above); classic 5-stage with full forwarding, branch in EX = N+4+S+2T; original 2-stage = N+1+T
(branch penalty 1, no hazards). *The real 2-stage cannot run these programs (no BNE/JAL/shifts...), so its column
is hypothetical.* None of these are RTL simulation results or timing results.

| program | N | T | S | 8-stage | CPI | 5-stage | CPI | 2-stage* | CPI |
|---|---|---|---|---|---|---|---|---|---|
| t1_alu | 28 | 0 | 0 | 35 | 1.25 | 32 | 1.14 | 29 | 1.04 |
| t2_forward | 42 | 1 | 0 | 53 | 1.26 | 48 | 1.14 | 44 | 1.05 |
| t3_loadstore | 52 | 1 | 4 | 67 | 1.29 | 62 | 1.19 | 54 | 1.04 |
| t4_branch | 62 | 14 | 0 | 125 | 2.02 | 94 | 1.52 | 77 | 1.24 |
| t5_jump | 27 | 10 | 1 | 75 | 2.78 | 52 | 1.93 | 38 | 1.41 |
| t6_bench | 139 | 21 | 16 | 246 | 1.77 | 201 | 1.45 | 161 | 1.16 |
| t7_system | 5 | 0 | 0 | 12 | 2.40 | 9 | 1.80 | 6 | 1.20 |

**Interpretation.** Latency of one instruction = 8 cycles (5 in the 5-stage). Throughput approaches 1 instr/cycle
once full (IPC -> 1), so CPI = 1 + (fill + penalties)/N; short programs are dominated by fill/drain (7 cycles).
Branch penalty grows 2 -> 4 and load-use stays 1 because data returns in MEM2. Deeper pipelining *can* allow a
shorter clock period (less logic per stage) but adds registers, forwarding paths and larger flush penalties, so
instruction count x CPI rises; whether the net time improves depends on achieved frequency. **ModelSim shows
cycle counts only; maximum frequency needs synthesis + static timing analysis (e.g. Quartus), which has not been
done, so no frequency or speed-up figure is claimed here.** Note the long MEM2->forward->ALU->branch-target
path is the likely critical path.

## 8. Next steps
1. Run `do sim/run_all.do`, send me any `vlog` error or the first `FAIL` lines.
2. Then: waveform screenshots (Section 6 of the README lists the signals), Quartus timing run, and optionally
   a 2-bit branch predictor to cut the 4-cycle penalty.
