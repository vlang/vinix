section .text
bits 64

global pt_flush:
    mov cr3, rdi
    ret