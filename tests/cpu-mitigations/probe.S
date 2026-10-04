.text
.global mitigation_syscall_probe
.type mitigation_syscall_probe,@function
mitigation_syscall_probe:
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15
    mov $0x12345678, %rbx
    mov $0x12345679, %rbp
    mov $0x1234567a, %r12
    mov $0x1234567b, %r13
    mov $0x1234567c, %r14
    mov $0x1234567d, %r15
    mov $0x12345670, %rdi
    mov $0x12345671, %rsi
    mov $0x12345672, %rdx
    mov $0x12345673, %r8
    mov $0x12345674, %r9
    mov $0x12345675, %r10
    mov $39, %eax
    syscall
    test %rax, %rax
    jle 1f
    cmp $0x12345678, %rbx
    jne 1f
    cmp $0x12345679, %rbp
    jne 1f
    cmp $0x1234567a, %r12
    jne 1f
    cmp $0x1234567b, %r13
    jne 1f
    cmp $0x1234567c, %r14
    jne 1f
    cmp $0x1234567d, %r15
    jne 1f
    cmp $0x12345670, %rdi
    jne 1f
    cmp $0x12345671, %rsi
    jne 1f
    cmp $0x12345672, %rdx
    jne 1f
    cmp $0x12345673, %r8
    jne 1f
    cmp $0x12345674, %r9
    jne 1f
    cmp $0x12345675, %r10
    jne 1f
    mov $1, %eax
    jmp 2f
1:
    xor %eax, %eax
2:
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret
.size mitigation_syscall_probe, .-mitigation_syscall_probe
.section .note.GNU-stack,"",@progbits
