section .text
bits 64

; Output byte to port
global outb
outb:
    mov rax, rsi
    mov rdx, rdi
    out dx, al
    ret

; Output word (2 byte) to port
global outw
outw:
    mov rax, rsi
    mov rdx, rdi
    out dx, ax
    ret

; Output long (4 byte) to port
global outl
outl:
    mov rax, rsi
    mov rdx, rdi
    out dx, eax
    ret

; Fetch one byte of input from port
global inb
inb:
    mov rdx, rdi
    xor rax, rax
    in al, dx
    ret

; Fetch a word (2 byte) of input from port
global inw
inw:
    mov rdx, rdi
    xor rax, rax
    in ax, dx
    ret

; Fetch a long (4 byte) of input from port
global inl
inl:
    mov rdx, rdi
    xor rax, rax
    in eax, dx
    ret
