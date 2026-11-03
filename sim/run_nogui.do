# Same without waveforms (fast): vsim -c -do sim/run_nogui.do
do sim/compile.do
vsim -c work.tb_riscv_8stage
run -all
quit -f
