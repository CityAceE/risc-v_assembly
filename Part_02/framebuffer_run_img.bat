@set file=framebuffer

"c:\Program Files\qemu\qemu-system-riscv32.exe" -M virt -serial stdio -device VGA -bios none -kernel %file%.img

@rem pause 0
