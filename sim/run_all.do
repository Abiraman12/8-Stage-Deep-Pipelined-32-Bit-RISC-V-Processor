# One-shot: compile, simulate with waveforms, run all tests
do sim/compile.do
vsim -voptargs=+acc work.tb_riscv_8stage
do sim/wave.do
run -all
