# T3: loads, stores, sign extension, sub-word stores, load-use hazards
lui  x1,0x81C3A
addi x1,x1,0x5F7     # x1 = 0x81C3A5F7
sw   x1,0(x0)
sw   x1,8(x0)
lw   x2,0(x0)
addi x3,x0,1
lb   x4,0(x0)        # 0xFFFFFFF7
lb   x5,1(x0)        # 0xFFFFFFA5
lb   x6,2(x0)        # 0xFFFFFFC3
lb   x7,3(x0)        # 0xFFFFFF81
lbu  x8,0(x0)        # 0xF7
lbu  x9,3(x0)        # 0x81
lh   x10,0(x0)       # 0xFFFFA5F7
lh   x11,2(x0)       # 0xFFFF81C3
lhu  x12,0(x0)       # 0xA5F7
lhu  x13,2(x0)       # 0x81C3
addi x14,x0,0x11
sb   x14,12(x0)
addi x14,x0,0x22
sb   x14,13(x0)
addi x14,x0,0x33
sb   x14,14(x0)
addi x14,x0,0x44
sb   x14,15(x0)
lw   x15,12(x0)      # 0x44332211
addi x16,x0,0x7FF
sh   x16,16(x0)
sh   x16,18(x0)
lw   x17,16(x0)      # 0x07FF07FF
sw   x1,20(x0)
sb   x0,20(x0)
lw   x18,20(x0)      # 0x81C3A500
addi x19,x0,0x123
sw   x19,24(x0)
lw   x20,24(x0)      # store then load, back to back
lw   x21,0(x0)
add  x22,x21,x21     # load-use (1 stall)
lw   x23,0(x0)
nop
add  x24,x23,x0      # distance 2, no stall
lw   x25,0(x0)
sw   x25,28(x0)      # load -> store data (1 stall)
addi x29,x0,0x4D
sw   x29,36(x0)
addi x26,x0,36
sw   x26,32(x0)
lw   x27,32(x0)
lw   x28,0(x27)      # load -> base register (1 stall)
lw   x30,0(x0)
bne  x30,x0,tgt      # load -> branch operand (1 stall), taken
addi x31,x0,1        # wrong path
tgt: addi x31,x0,2
ecall
