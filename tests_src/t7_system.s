# T7: FENCE is a NOP; EBREAK halts and younger instructions must have no effect
addi x1,x0,1
fence
addi x2,x0,2
sw   x2,0(x0)
ebreak
addi x3,x0,111
sw   x2,4(x0)
addi x4,x0,111
