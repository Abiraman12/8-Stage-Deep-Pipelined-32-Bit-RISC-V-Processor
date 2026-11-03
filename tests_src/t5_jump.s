# T5: JAL, JALR, link registers, call/return, JALR forwarding and load-use
jal  x1,f1
addi x10,x0,111
addi x11,x0,111
f1:  addi x10,x0,1
jal  x5,func
addi x12,x0,2
beq  x0,x0,after
func: addi x13,x0,3
jalr x0,0(x5)
addi x14,x0,111
after: auipc x6,0
addi x6,x6,20
jalr x7,0(x6)
addi x15,x0,111
addi x16,x0,111
addi x15,x0,4
auipc x9,0
addi x9,x9,17        # odd target, bit 0 must be cleared
jalr x0,0(x9)
addi x18,x0,111
addi x19,x0,5
auipc x22,0
addi x22,x22,24
sw   x22,40(x0)
lw   x23,40(x0)
jalr x24,0(x23)      # load -> jalr base (1 stall)
addi x25,x0,111
addi x25,x0,6
jal  x26,Lk
addi x27,x0,111
Lk:  add x28,x26,x0
jal  x0,J1
nop
J1:  jal x0,J2
addi x29,x0,111
J2:  addi x29,x0,7
ecall
