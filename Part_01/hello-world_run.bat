@set file=hello-world

"c:\Program Files\qemu\qemu-system-riscv64.exe" -M virt -nographic -bios none -kernel %file%.img
