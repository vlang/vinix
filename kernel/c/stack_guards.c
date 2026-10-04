#include <stdint.h>

/* Fatal/test markers must reach serial even in PROD, without a console lock. */
void vinix_stack_guard_message(const char *message) {
#if defined(__aarch64__)
    extern void aarch64__uart__putc(uint8_t);
    while (*message) aarch64__uart__putc((uint8_t)*message++);
#else
    extern void serial__panic_out(uint8_t);
    while (*message) serial__panic_out((uint8_t)*message++);
#endif
}

static void guard_hex(uint64_t value) {
    static const char digits[] = "0123456789abcdef";
    char digit[2] = {0, 0};
    for (int shift = 60; shift >= 0; shift -= 4) {
        digit[0] = digits[(value >> shift) & 15];
        vinix_stack_guard_message(digit);
    }
}

/* Print scalar evidence before the fatal marker; no console lock or heap. */
void vinix_stack_guard_diagnostic(uint64_t sp, uint64_t pc, uint64_t address) {
    vinix_stack_guard_message("STACK-GUARD state sp=0x");
    guard_hex(sp);
    vinix_stack_guard_message(" pc=0x");
    guard_hex(pc);
    vinix_stack_guard_message(" address=0x");
    guard_hex(address);
    vinix_stack_guard_message("\n");
}

/* These leaf probes are recovered only by exact instruction/address matches
 * in an opt-in test kernel. No general kernel-fault recovery is installed. */
#if defined(__aarch64__)
#define GUARD_REGISTERS \
    "mov x15, #0x1357\nmovk x15, #0x2468, lsl #16\n" \
    "movk x15, #0x9abc, lsl #32\nmovk x15, #0xdef0, lsl #48\n" \
    "mov x16, x15\nmov x17, x15\nmov x2, x15\n"
#define GUARD_VERIFY \
    "cmp x15, x2\ncset x0, eq\ncmp x16, x2\ncset x1, eq\n" \
    "and x0, x0, x1\ncmp x17, x2\ncset x1, eq\nand x0, x0, x1\nret\n"
__attribute__((naked)) uint64_t vinix_guard_probe_read(uint64_t address) {
    __asm__ volatile(GUARD_REGISTERS
        ".global vinix_guard_read_fault\nvinix_guard_read_fault:\nldrb w1, [x0]\n"
        ".global vinix_guard_read_resume\nvinix_guard_read_resume:\n" GUARD_VERIFY);
}
__attribute__((naked)) uint64_t vinix_guard_probe_write(uint64_t address) {
    __asm__ volatile(GUARD_REGISTERS
        ".global vinix_guard_write_fault\nvinix_guard_write_fault:\nstrb wzr, [x0]\n"
        ".global vinix_guard_write_resume\nvinix_guard_write_resume:\n" GUARD_VERIFY);
}
__attribute__((naked)) uint64_t vinix_guard_probe_stack(uint64_t base) {
    __asm__ volatile("stp x19, x20, [sp, #-32]!\nstp x21, x30, [sp, #16]\n"
        "mov x19, sp\nmrs x20, spsel\nmsr spsel, #1\nmov x21, sp\nmov sp, x0\n"
        ".global vinix_guard_stack_fault\nvinix_guard_stack_fault:\nstp xzr, xzr, [sp, #-16]!\n"
        ".global vinix_guard_stack_resume\nvinix_guard_stack_resume:\nmov sp, x21\n"
        "cbnz x20, 1f\nmsr spsel, #0\n1:\nmov sp, x19\n"
        "ldp x21, x30, [sp, #16]\nldp x19, x20, [sp], #32\nmov x0, #1\nret\n");
}
#else
__attribute__((naked, noreturn)) void vinix_enter_idle(uint64_t top, void *entry, void *arg) {
    __asm__ volatile("cli\nmov %rdi, %rsp\nand $-16, %rsp\nsub $8, %rsp\n"
                     "movq $0, (%rsp)\nmov %rdx, %rdi\njmp __x86_indirect_thunk_rsi\n");
}
__attribute__((naked)) uint64_t vinix_guard_probe_read(uint64_t address) {
    __asm__ volatile(".global vinix_guard_read_fault\nvinix_guard_read_fault:\nmovb (%rdi), %al\n"
        ".global vinix_guard_read_resume\nvinix_guard_read_resume:\nmov $1, %eax\nret\n");
}
__attribute__((naked)) uint64_t vinix_guard_probe_write(uint64_t address) {
    __asm__ volatile(".global vinix_guard_write_fault\nvinix_guard_write_fault:\nmovb $0, (%rdi)\n"
        ".global vinix_guard_write_resume\nvinix_guard_write_resume:\nmov $1, %eax\nret\n");
}
__attribute__((naked)) uint64_t vinix_guard_probe_stack(uint64_t base) {
    __asm__ volatile("mov %rsp, %r11\nmov %rdi, %rsp\n"
        ".global vinix_guard_stack_fault\nvinix_guard_stack_fault:\npushq $0\n"
        ".global vinix_guard_stack_resume\nvinix_guard_stack_resume:\nmov %r11, %rsp\n"
        "mov $1, %eax\nret\n");
}
#endif
