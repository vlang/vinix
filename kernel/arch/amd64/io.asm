section .text
code64

global outb
outb:
  push rbp
  mov rbp, rsp
  mov rax, rsi
  mov rdx, rdi
  out dx, al
  pop rbp
  ret

global outw
outw:
  push rbp
  mov rbp, rsp
  mov rax, rsi
  mov rdx, rdi
  out dx, ax
  pop rbp
  ret

global outl
outl:
  push rbp
  mov rbp, rsp
  mov rax, rsi
  mov rdx, rdi
  out dx, eax
  pop rbp
  ret

global inb
inb:
  push rbp
  mov rbp, rsp
  mov rdx, rdi
  xor rax, rax
  in al, dx
  pop rbp
  ret

global inw
inw:
  push rbp
  mov rbp, rsp
  mov rdx, rdi
  xor rax, rax
  in ax, dx
  pop rbp
  ret

global inl
inl:
  push rbp
  mov rbp, rsp
  mov rdx, rdi
  xor rax, rax
  in eax, dx
  pop rbp
  ret