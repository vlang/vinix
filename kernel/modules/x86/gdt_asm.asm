section .data

gdt_ptr:
    .limit dw gdt.end - gdt - 1
    .base  dq gdt

gdt:
    dq 0x0000000000000000      ; null ptr
    dq 0x00209a0000000000      ; kernel code 64
    dq 0x0000920000000000      ; kernel data 64
    dq 0x0000f20000000000      ; user data 64
    dq 0x0020fa0000000000      ; user code 64
.end:

section .text

global gdt_reload
gdt_reload:
    lgdt [rel gdt_ptr]
    push 0x08
    lea rax, [rel .reentry]
    push rax
    retfq
.reentry:
    mov eax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    ret
