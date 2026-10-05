/* Register clobbers: RAX, RCX, RDX only. Use after saving the GPR frame.
 * The records are boot-owned, per logical CPU; interrupts must be disabled. */
.macro VINIX_SPEC_POLICY number
    .ifc \number,gs0
    mov %gs:0, %rax
    .else
    mov %\number, %rax
    .endif
    shl $5, %rax
    mov vinix_x86_mitigation_policies(%rip), %rdx
    add %rax, %rdx
.endm

/* RSB overwrite before any return after a user entry or context switch.
 * Every inserted prediction lands in a speculation trap. Restore the stack
 * without RET, preserving both its contents above RSP and every GPR. */
.macro VINIX_RSB_FILL
    .rept 32
    call 991f
990:
    pause
    lfence
    jmp 990b
991:
    .endr
    add $256, %rsp
.endm

.macro VINIX_SPEC_ENTER
    VINIX_SPEC_POLICY gs0
    testq $2, 16(%rdx)
    jz 992f
    mov 0(%rdx), %rax
    mov %rax, %rdx
    shr $32, %rdx
    mov $0x48, %ecx
    wrmsr
992:
.endm

/* Flush predictors after every actual thread switch, including a switch to
 * a thread paused inside the kernel. Consume it at that CPU's next user
 * return; ordinary syscalls by the same thread do not issue IBPB. */
.macro VINIX_SPEC_SWITCH number
    VINIX_SPEC_POLICY \number
    testq $1, 16(%rdx)
    jz 993f
    orq $256, 16(%rdx)
993:
.endm

.macro VINIX_SPEC_RETURN number, error_offset
    VINIX_SPEC_POLICY \number
    testq $256, 16(%rdx)
    jz 994f
    andq $-257, 16(%rdx)
    mov $1, %eax
    xor %edx, %edx
    mov $0x49, %ecx
    wrmsr
    VINIX_SPEC_POLICY \number
994:
    testq $2, 16(%rdx)
    jz 995f
    mov 8(%rdx), %rax
    mov %rax, %rdx
    shr $32, %rdx
    mov $0x48, %ecx
    wrmsr
    VINIX_SPEC_POLICY \number
995:
    mov 16(%rdx), %rax
    and $8, %eax
    mov %rax, \error_offset(%rsp)
.endm

/* The error-code slot is dead after the handlers finish. It carries a
 * capability marker until all GPRs have been restored. VERW preserves them;
 * CMP changes only flags, which IRETQ/SYSRETQ restores from the user frame. */
.macro VINIX_SPEC_CLEAR
    cmpq $0, (%rsp)
    je 996f
    verw vinix_x86_verw_selector(%rip)
996:
    // Resolve a required clear before speculation can reach user return.
    lfence
.endm
