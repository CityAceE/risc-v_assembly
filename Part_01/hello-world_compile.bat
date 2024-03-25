@set file=hello-world
@set toolchain=c:\SysGCC\risc-v\bin\riscv64-unknown-elf

@%toolchain%-as -o %file%.o %file%.s 
@%toolchain%-ld -o %file%.elf -Ttext 0x80000000 %file%.o
@%toolchain%-objcopy -O binary %file%.elf %file%.img

@if exist %file%.o del %file%.o
@if exist %file%.elf del %file%.elf

@pause 0