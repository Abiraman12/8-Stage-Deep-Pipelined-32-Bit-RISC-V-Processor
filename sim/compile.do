# Compile all RTL + testbench (run from the project root folder)
catch {quit -sim}
if {![file exists work]} {vlib work}
vmap work work
vlog rtl/program_counter.v rtl/instruction_memory.v rtl/instruction_decoder.v rtl/control_unit.v rtl/immediate_generator.v rtl/register_file.v rtl/alu.v rtl/branch_control.v rtl/forwarding_unit.v rtl/hazard_detection_unit.v rtl/data_memory.v rtl/load_extender.v rtl/if1_if2_register.v rtl/if2_id_register.v rtl/id_rr_register.v rtl/rr_ex_register.v rtl/ex_mem1_register.v rtl/mem1_mem2_register.v rtl/mem2_wb_register.v rtl/riscv_8stage_top.v tb/tb_riscv_8stage.v
