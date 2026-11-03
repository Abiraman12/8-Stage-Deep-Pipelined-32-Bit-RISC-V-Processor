addi x1,x0,5
addi x2,x1,1
sw   x2,0(x0)
lw   x3,0(x0)
add  x4,x3,x1
beq  x4,x4,L
addi x5,x0,111
L:   addi x6,x0,7
ecall
