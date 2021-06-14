#include <stdint.h>
#include <stddef.h>

void lib__syscall_kprint(void *, char *message);

__attribute__((used)) void *syscall_table[] = {
    lib__syscall_kprint
};

__attribute__((naked, used))
void interrupt_thunk(void) {
    asm (
        "interrupt_thunk_begin:"
        "push $0\n\t"
        "push %r15\n\t"
        "push %r14\n\t"
        "push %r13\n\t"
        "push %r12\n\t"
        "push %r11\n\t"
        "push %r10\n\t"
        "push %r9\n\t"
        "push %r8\n\t"
        "push %rbp\n\t"
        "push %rdi\n\t"
        "push %rsi\n\t"
        "push %rdx\n\t"
        "push %rcx\n\t"
        "push %rbx\n\t"
        "push %rax\n\t"
        "mov %es, %eax\n\t"
        "push %rax\n\t"
        "mov %ds, %eax\n\t"
        "push %rax\n\t"
        "cld\n\t"
        "mov $0x30, %eax\n\t"
        "mov %eax, %ds\n\t"
        "mov %eax, %es\n\t"
        "mov %eax, %ss\n\t"
        "mov %rsp, %rsi\n\t"
        ".byte 0xbf\n\t"
        "interrupt_thunk_number: .long 0\n\t"
        ".byte 0x48\n\t"
        ".byte 0xbb\n\t"
        "interrupt_thunk_offset: .quad 0\n\t"
        "call *(%rbx)\n\t"
        "pop %rax\n\t"
        "mov %eax, %ds\n\t"
        "pop %rax\n\t"
        "mov %eax, %es\n\t"
        "pop %rax\n\t"
        "pop %rbx\n\t"
        "pop %rcx\n\t"
        "pop %rdx\n\t"
        "pop %rsi\n\t"
        "pop %rdi\n\t"
        "pop %rbp\n\t"
        "pop %r8\n\t"
        "pop %r9\n\t"
        "pop %r10\n\t"
        "pop %r11\n\t"
        "pop %r12\n\t"
        "pop %r13\n\t"
        "pop %r14\n\t"
        "pop %r15\n\t"
        "add $8, %rsp\n\t"
        "iretq\n\t"
        "interrupt_thunk_end:\n\t"
        "interrupt_thunk_size: .quad interrupt_thunk_end - interrupt_thunk_begin\n\t"
        "interrupt_thunk_storage: .space (interrupt_thunk_end - interrupt_thunk_begin) * 256\n\t"
    );
}

extern char interrupt_thunk_begin[], interrupt_thunk_end[], interrupt_thunk_storage[];
extern uint64_t interrupt_thunk_offset;
extern uint32_t interrupt_thunk_number;
extern uint64_t interrupt_thunk_size;
extern void *interrupt_table[];
extern void *interrupt_thunks[];

void *memcpy(void *dest, const void *src, size_t n);

void prepare_interrupt_thunks(void) {
    for (size_t i = 0; i < 256; i++) {
        interrupt_thunk_offset = (uintptr_t)&interrupt_table[i];
        interrupt_thunk_number = i;
        void *ptr = interrupt_thunk_storage + i * interrupt_thunk_size;
        memcpy(ptr, interrupt_thunk_begin, interrupt_thunk_size);
        uint64_t shift = 0;
        switch (i) {
            case 8: case 10: case 11: case 12: case 13: case 14:
            case 17: case 30:
                shift = 2;
                break;
        }
        interrupt_thunks[i] = ptr + shift;
    }
}
