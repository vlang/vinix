#include <stdint.h>
#include <stddef.h>

__attribute__((naked, used))
void interrupt_thunk(void) {
    asm (
        "interrupt_thunk_begin:"
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
        "mov %rsp, %rsi\n\t"
        ".byte 0xbf\n\t"
        "interrupt_thunk_number: .long 0\n\t"
        ".byte 0x48\n\t"
        ".byte 0xbb\n\t"
        "interrupt_thunk_offset: .quad 0\n\t"
        "call *(%rbx)\n\t"
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
        interrupt_thunks[i] = ptr;
    }
}
