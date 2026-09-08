.section .rodata
message:
    .ascii "VINIX X86_64 TRANSLATION: PASS\n"
.set message_length, . - message

.section .text
.global _start
.type _start, @function
_start:
    # Exercise the sparse virtual address reservations used by Wine. Most of
    # these succeed; the range containing this executable is expected to be
    # rejected by MAP_FIXED_NOREPLACE.
    mov $0x10000, %r12
0:
    mov $9, %rax
    mov %r12, %rdi
    mov $0x10000, %rsi
    xor %edx, %edx
    mov $0x100022, %r10d
    mov $-1, %r8
    xor %r9d, %r9d
    syscall
    add $0x10000, %r12
    cmp $0x100000, %r12
    jb 0b

    # A normal writable allocation must still succeed after those address
    # probes. This caught the mmap interaction that initially stalled Wine.
    mov $9, %rax
    xor %edi, %edi
    mov $0x200000, %rsi
    mov $3, %edx
    mov $0x22, %r10d
    mov $-1, %r8
    xor %r9d, %r9d
    syscall
    cmp $-4095, %rax
    jae 1f
    mov %rax, %r13

    mov $11, %rax
    mov %r13, %rdi
    mov $0x200000, %rsi
    syscall

    mov $1, %rax
    mov $1, %rdi
    lea message(%rip), %rsi
    mov $message_length, %rdx
    syscall

    cmp $message_length, %rax
    jne 1f
    xor %edi, %edi
    jmp 2f
1:
    mov $1, %edi
2:
    mov $60, %rax
    syscall
.size _start, . - _start
