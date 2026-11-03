# T1: arithmetic / logic / shifts / compares / LUI / AUIPC / x0 behaviour (no loads, no branches)
addi x1,x0,5
addi x2,x0,7
add  x3,x1,x2        # 12
sub  x4,x3,x1        # 7
and  x5,x3,x2        # 4
or   x6,x1,x2        # 7
xor  x7,x1,x2        # 2
sll  x8,x1,x2        # 640
srl  x9,x3,x1        # 0
addi x10,x0,-8
sra  x11,x10,x1      # -1
srl  x12,x10,x2      # 0x01FFFFFF
slt  x13,x10,x1      # 1
sltu x14,x10,x1      # 0
slti x15,x10,-7      # 1
sltiu x16,x1,6       # 1
xori x17,x1,15       # 10
ori  x18,x1,0x70     # 0x75
andi x19,x3,10       # 8
slli x20,x1,4        # 80
srli x21,x10,28      # 15
srai x22,x10,1       # -4
lui  x23,0x12345     # 0x12345000
auipc x24,1          # pc(=92)+0x1000
addi x0,x1,100       # write to x0 must be ignored
add  x25,x0,x1       # 5
sub  x26,x0,x1       # -5
ecall
