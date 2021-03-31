section .text

global inb
inb:
    mov edx, edi
    xor eax, eax
    in al, dx
    ret

global outb
outb:
    mov edx, edi
    mov eax, esi
    out dx, al
    ret
