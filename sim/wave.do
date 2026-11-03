# Waveform setup for tb_riscv_8stage
onerror {resume}
add wave -divider {Clock / reset}
add wave -noupdate /tb_riscv_8stage/clk
add wave -noupdate /tb_riscv_8stage/reset
add wave -divider {Pipeline occupancy  (bit0=IF1 ... bit7=WB)}
add wave -noupdate -radix hex  /tb_riscv_8stage/dbg_pc
add wave -noupdate -radix binary /tb_riscv_8stage/dbg_valid
add wave -noupdate -radix hex  /tb_riscv_8stage/dbg_instr_if2
add wave -noupdate -radix hex  /tb_riscv_8stage/dbg_instr_id
add wave -noupdate -radix hex  /tb_riscv_8stage/dbg_instr_rr
add wave -noupdate -radix hex  /tb_riscv_8stage/dbg_instr_ex
add wave -noupdate -radix hex  /tb_riscv_8stage/dbg_instr_mem1
add wave -noupdate -radix hex  /tb_riscv_8stage/dbg_instr_mem2
add wave -noupdate -radix hex  /tb_riscv_8stage/dbg_instr_wb
add wave -divider {Hazards}
add wave -noupdate /tb_riscv_8stage/dbg_load_use_stall
add wave -noupdate /tb_riscv_8stage/dbg_redirect
add wave -noupdate /tb_riscv_8stage/dbg_flush
add wave -noupdate /tb_riscv_8stage/dbg_halted
add wave -noupdate -radix unsigned /tb_riscv_8stage/dbg_fwd_a
add wave -noupdate -radix unsigned /tb_riscv_8stage/dbg_fwd_b
add wave -divider {EX / memory}
add wave -noupdate -radix hex /tb_riscv_8stage/dbg_alu_result
add wave -noupdate /tb_riscv_8stage/dbg_dmem_re
add wave -noupdate /tb_riscv_8stage/dbg_dmem_we
add wave -noupdate -radix hex /tb_riscv_8stage/dbg_dmem_addr
add wave -noupdate -radix hex /tb_riscv_8stage/dbg_dmem_wdata
add wave -divider {Write-back / retirement}
add wave -noupdate /tb_riscv_8stage/dbg_wb_we
add wave -noupdate -radix unsigned /tb_riscv_8stage/dbg_wb_rd
add wave -noupdate -radix hex /tb_riscv_8stage/dbg_wb_data
add wave -noupdate /tb_riscv_8stage/retire_valid
add wave -noupdate -radix hex /tb_riscv_8stage/retire_pc
add wave -divider {Counters}
add wave -noupdate -radix unsigned /tb_riscv_8stage/cycle_count
add wave -noupdate -radix unsigned /tb_riscv_8stage/retired_count
add wave -noupdate -radix unsigned /tb_riscv_8stage/load_use_stall_count
add wave -noupdate -radix unsigned /tb_riscv_8stage/redirect_count
wave zoom full
