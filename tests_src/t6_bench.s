# T6: small benchmark - fill array, sum it (load-use every iteration), copy it
addi x1,x0,64
addi x2,x0,8
addi x3,x0,1
fill: sw x3,0(x1)
addi x3,x3,3
addi x1,x1,4
addi x2,x2,-1
bne  x2,x0,fill
addi x1,x0,64
addi x2,x0,8
addi x4,x0,0
sum: lw x5,0(x1)
add  x4,x4,x5
addi x1,x1,4
addi x2,x2,-1
bne  x2,x0,sum
sw   x4,0(x0)        # 92
addi x1,x0,64
addi x6,x0,128
addi x2,x0,8
copy: lw x7,0(x1)
sw   x7,0(x6)
addi x1,x1,4
addi x6,x6,4
addi x2,x2,-1
bne  x2,x0,copy
ecall
