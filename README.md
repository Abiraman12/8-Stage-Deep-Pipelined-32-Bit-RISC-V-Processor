# 8-Stage Pipelined 32-bit RV32I Processor (Verilog-2001, ModelSim 2020.3)

## Verification status (read this first)
The sandbox that produced these files had **no Verilog simulator** (no iverilog/ModelSim, no network),
so the RTL and testbench have **NOT been compiled or simulated yet**. What *was* checked:

| Check | Tool | Result |
|---|---|---|
| Assembler encodings vs known RISC-V encodings (11 + 2 from your 2-stage TB) | `tools/rvasm.py` | pass |
| Golden ISS vs 78 hand-calculated values used in the TB | script | 0 disagreements |
| Structural lint of all 20 RTL modules (undeclared names, port names, connections, widths) | `tools/lint_check.py` | 0 errors; 3/3 injected bugs caught |
| Cycle-level Python model of this exact microarchitecture vs ISS, 8 programs (regs, memory, retire order, stalls, flushes, cycle count) | `tools/pipeline_model.py` | all MATCH; 4/4 injected design bugs caught |

So the **design logic is validated; the Verilog syntax/semantics are not yet**. Your first ModelSim run is the
real test. If `vlog` prints an error, send me the `# ** Error:` line and I will fix it.

## Folder structure
```
riscv8/
  rtl/    20 Verilog modules (one per file) + riscv_8stage_top.v
  tb/     tb_riscv_8stage.v          (self-checking)
  tests/  tN_*.hex  program + golden regs/mem/retire-PCs/stats (generated)
  tests_src/ *.s    assembly sources of the 7 test programs (+ demo_timing.s)
  sim/    compile.do  wave.do  run_all.do  run_nogui.do
  tools/  rvasm.py (assembler+ISS)  pipeline_model.py  lint_check.py  gen_pipe_regs.py
  docs/   ARCHITECTURE.md  timing_diagram_table.md
```
The `.hex` files are already generated. Re-generate only if you edit a `.s` file: `python tools/rvasm.py`.

## Run in ModelSim (Windows)
Put the whole `riscv8` folder somewhere, e.g. `C:/Users/YOU/Documents/riscv8`. Do **not** put files inside `work`.
The testbench opens `tests/...` with relative paths, so ModelSim's current folder must be the project root.
```
cd {C:/Users/YOU/Documents/riscv8}
pwd
dir rtl/*.v
dir tests/*.hex
do sim/run_all.do
```
`run_all.do` = `vlib work`, `vmap work work`, `vlog` (all files), `vsim -voptargs=+acc work.tb_riscv_8stage`,
`add wave` list, `run -all`. When it ends with `$finish`, ModelSim asks "Are you sure you want to finish?" -> click **No**
to keep the waveform. Without waves: `do sim/run_nogui.do`.

## Expected result
The console prints one block per test, ending in `T1 PASS` ... `T7 PASS` and
`ALL 8 TESTS PASSED  (T0..T7)`. Expected counters (from the ISS/model, **not yet from a real run**):

| Test | retired | load-use stalls | redirects | cycles |
|---|---|---|---|---|
| T1 ALU | 28 | 0 | 0 | 35 |
| T2 forwarding | 42 | 0 | 1 | 53 |
| T3 load/store | 52 | 4 | 1 | 67 |
| T4 branches | 62 | 0 | 14 | 125 |
| T5 jumps | 27 | 1 | 10 | 75 |
| T6 benchmark | 139 | 16 | 21 | 246 |
| T7 system | 5 | 0 | 0 | 12 |

If any cycle/stall count differs from this table, that is a real RTL bug: the TB prints which counter.

## Debugging procedure
1. Read the first `FAIL:` line. Register/memory FAIL -> look at the retire order FAIL (if any) first.
2. Wave: `dbg_valid`, `dbg_instr_*` (what is in each stage), `dbg_fwd_a/b` (0 none,1 MEM1,2 MEM2,3 WB),
   `dbg_load_use_stall`, `dbg_redirect`, `dbg_flush`.
3. Wrong value after back-to-back ops -> forwarding_unit / mux in `riscv_8stage_top` (EX section).
4. Wrong value after a load -> hazard_detection_unit, `load_extender`, `data_memory` timing.
5. Extra instruction effects after a branch -> flush wiring (`flush_younger`, `flush_rr_ex`).
Troubleshooting: `Failed to open design unit file` = wrong folder (run `pwd`, `dir rtl/*.v`);
`$readmemh ... cannot open file` = ModelSim not started in the project root.
