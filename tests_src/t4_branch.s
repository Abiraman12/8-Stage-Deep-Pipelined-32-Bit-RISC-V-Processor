# T4: all six branch types taken / not taken, wrong-path protection, loops
addi x1,x0,5
addi x2,x0,5
addi x3,x0,-1
addi x4,x0,1
beq  x1,x2,b1
addi x10,x0,111
sw   x1,4(x0)        # wrong-path store: must NOT reach memory
addi x11,x0,111
addi x12,x0,111
b1:  addi x10,x0,1
beq  x1,x4,bad1
addi x11,x0,2
bad1: nop
bne  x1,x4,b2
addi x12,x0,111
b2:  addi x12,x0,3
bne  x1,x2,bad2
addi x13,x0,4
bad2: nop
blt  x3,x4,b3
addi x14,x0,111
b3:  addi x14,x0,5
blt  x4,x3,bad3
addi x15,x0,6
bad3: nop
bge  x4,x3,b4
addi x16,x0,111
b4:  addi x16,x0,7
bge  x1,x2,b4b
addi x17,x0,111
b4b: addi x17,x0,8
bge  x3,x4,bad4
addi x18,x0,9
bad4: nop
bltu x4,x3,b5
addi x19,x0,111
b5:  addi x19,x0,10
bltu x3,x4,bad5
addi x21,x0,11
bad5: nop
bgeu x3,x4,b6
addi x22,x0,111
b6:  addi x22,x0,12
bgeu x4,x3,bad6
addi x23,x0,13
bad6: nop
addi x24,x0,0
addi x25,x0,5
loop: add x24,x24,x25
addi x25,x25,-1
bne  x25,x0,loop
sw   x24,0(x0)       # 15
beq  x0,x0,c1
addi x26,x0,111
c1:  beq x0,x0,c2
addi x26,x0,111
c2:  addi x26,x0,14
addi x27,x0,3
addi x28,x0,3
beq  x27,x28,c3
addi x29,x0,111
c3:  addi x29,x0,15
ecall
