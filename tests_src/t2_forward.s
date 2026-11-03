# T2: data forwarding at every distance, priority, x0, store data, branch operands
addi x1,x0,1
addi x2,x1,1         # d1 -> 2
addi x3,x2,1         # d1 -> 3
add  x4,x3,x2        # x3 d1, x2 d2 -> 5
add  x5,x4,x1        # x4 d1 -> 6
addi x6,x0,10
nop
addi x7,x6,1         # d2 -> 11
addi x8,x0,20
nop
nop
addi x9,x8,1         # d3 (WB forward) -> 21
addi x10,x0,30
nop
nop
nop
addi x11,x10,1       # d4 (register-file bypass) -> 31
addi x12,x0,100
addi x12,x0,200      # newest writer must win
add  x13,x12,x0      # 200
addi x0,x0,55
add  x14,x0,x1       # x0 never forwarded -> 1
addi x0,x1,77
add  x15,x0,x0       # 0
addi x16,x0,3
addi x17,x0,4
add  x18,x16,x17     # 7 (two different forwarding sources)
addi x19,x0,0x55
sw   x19,0(x0)       # store data forwarded (d1)
addi x20,x0,0x66
nop
sw   x20,4(x0)       # store data forwarded (d2)
addi x21,x0,9
addi x22,x0,9
beq  x21,x22,ok1     # both branch operands forwarded, taken
addi x23,x0,1        # wrong path
ok1: addi x24,x0,2
addi x25,x0,1
add  x25,x25,x25     # 2
add  x25,x25,x25     # 4
add  x25,x25,x25     # 8
add  x25,x25,x25     # 16
ecall
