section .text
bits 64

global outb
outb:
  mov rax, rsi
  mov rdx, rdi
  out dx, al
  ret

global outw
outw:
  mov rax, rsi
  mov rdx, rdi
  out dx, ax
  ret

global outl
outl:
  mov rax, rsi
  mov rdx, rdi
  out dx, eax
  ret

global inb
inb:
  mov rdx, rdi
  xor rax, rax
  in al, dx
  ret

global inw
inw:
  mov rdx, rdi
  xor rax, rax
  in ax, dx
  ret

global inl
inl:
  mov rdx, rdi
  xor rax, rax
  in eax, dx
  ret