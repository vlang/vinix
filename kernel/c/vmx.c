#include "vmx.h"

#if defined(__x86_64__)

/* VMX instructions report VMfailInvalid in CF and VMfailValid in ZF. */
#define VMX_RESULT(instruction, operand)                                      \
    do {                                                                      \
        unsigned char failed;                                                 \
        __asm__ volatile(instruction " %1; setna %0"                         \
                         : "=rm"(failed)                                     \
                         : operand                                            \
                         : "cc", "memory");                                 \
        return failed ? -1 : 0;                                               \
    } while (0)

int vinix_vmx_on(uint64_t physical_address) {
    VMX_RESULT("vmxon", "m"(physical_address));
}

int vinix_vmx_off(void) {
    unsigned char failed;
    __asm__ volatile("vmxoff; setna %0"
                     : "=rm"(failed)
                     :
                     : "cc", "memory");
    return failed ? -1 : 0;
}

int vinix_vmx_clear(uint64_t physical_address) {
    VMX_RESULT("vmclear", "m"(physical_address));
}

int vinix_vmx_load(uint64_t physical_address) {
    VMX_RESULT("vmptrld", "m"(physical_address));
}

int vinix_vmx_write(uint64_t field, uint64_t value) {
    unsigned char failed;
    __asm__ volatile("vmwrite %1, %2; setna %0"
                     : "=rm"(failed)
                     : "r"(value), "r"(field)
                     : "cc", "memory");
    return failed ? -1 : 0;
}

int vinix_vmx_read(uint64_t field, uint64_t *value) {
    uint64_t result;
    unsigned char failed;
    __asm__ volatile("vmread %2, %1; setna %0"
                     : "=rm"(failed), "=r"(result)
                     : "r"(field)
                     : "cc", "memory");
    if (!failed)
        *value = result;
    return failed ? -1 : 0;
}

void vinix_vmx_fxsave(void *state) {
    __asm__ volatile("fxsave64 %0" : "=m"(*(char (*)[512])state) : : "memory");
}

void vinix_vmx_fxrstor(const void *state) {
    __asm__ volatile("fxrstor64 %0" : : "m"(*(const char (*)[512])state) : "memory");
}

void vinix_vmx_sgdt(struct vinix_vmx_descriptor *descriptor) {
    __asm__ volatile("sgdt %0" : "=m"(*descriptor));
}

void vinix_vmx_sidt(struct vinix_vmx_descriptor *descriptor) {
    __asm__ volatile("sidt %0" : "=m"(*descriptor));
}

#define READ_SELECTOR(name, instruction)                                     \
    uint16_t name(void) {                                                     \
        uint16_t selector;                                                    \
        __asm__ volatile(instruction " %0" : "=rm"(selector));              \
        return selector;                                                      \
    }

READ_SELECTOR(vinix_vmx_read_cs, "mov %%cs,")
READ_SELECTOR(vinix_vmx_read_ss, "mov %%ss,")
READ_SELECTOR(vinix_vmx_read_ds, "mov %%ds,")
READ_SELECTOR(vinix_vmx_read_es, "mov %%es,")
READ_SELECTOR(vinix_vmx_read_fs, "mov %%fs,")
READ_SELECTOR(vinix_vmx_read_gs, "mov %%gs,")
READ_SELECTOR(vinix_vmx_read_tr, "str")

/*
 * Enter the current VMCS and return after a VM exit. The VMCS host RSP points
 * at the saved register-block pointer, so that pointer survives while every
 * general-purpose register belongs to the guest.
 */
__asm__(
    ".text\n"
    ".global vinix_vmx_enter\n"
    ".type vinix_vmx_enter, @function\n"
    "vinix_vmx_enter:\n"
    "pushq %rbp\n"
    "pushq %rbx\n"
    "pushq %r12\n"
    "pushq %r13\n"
    "pushq %r14\n"
    "pushq %r15\n"
    "pushq %rdi\n"
    "movq $0x6c14, %rax\n"
    "vmwrite %rsp, %rax\n"
    "jna .Lvinix_vmx_failure\n"
    "leaq .Lvinix_vmx_exit(%rip), %r10\n"
    "movq $0x6c16, %rax\n"
    "vmwrite %r10, %rax\n"
    "jna .Lvinix_vmx_failure\n"
    "movq (%rsp), %rax\n"
    "movq 8(%rax), %rbx\n"
    "movq 16(%rax), %rcx\n"
    "movq 24(%rax), %rdx\n"
    "movq 32(%rax), %rsi\n"
    "movq 48(%rax), %rbp\n"
    "movq 56(%rax), %r8\n"
    "movq 64(%rax), %r9\n"
    "movq 72(%rax), %r10\n"
    "movq 80(%rax), %r11\n"
    "movq 88(%rax), %r12\n"
    "movq 96(%rax), %r13\n"
    "movq 104(%rax), %r14\n"
    "movq 112(%rax), %r15\n"
    "movq 40(%rax), %rdi\n"
    "movq (%rax), %rax\n"
    "vmlaunch\n"
    ".Lvinix_vmx_failure:\n"
    "movl $-1, %eax\n"
    "jmp .Lvinix_vmx_return\n"
    ".Lvinix_vmx_exit:\n"
    "cld\n"
    "pushq %rax\n"
    "pushq %r10\n"
    "movq 16(%rsp), %rax\n"
    "movq %rbx, 8(%rax)\n"
    "movq %rcx, 16(%rax)\n"
    "movq %rdx, 24(%rax)\n"
    "movq %rsi, 32(%rax)\n"
    "movq %rdi, 40(%rax)\n"
    "movq %rbp, 48(%rax)\n"
    "movq %r8, 56(%rax)\n"
    "movq %r9, 64(%rax)\n"
    "movq (%rsp), %r10\n"
    "movq %r10, 72(%rax)\n"
    "movq %r11, 80(%rax)\n"
    "movq %r12, 88(%rax)\n"
    "movq %r13, 96(%rax)\n"
    "movq %r14, 104(%rax)\n"
    "movq %r15, 112(%rax)\n"
    "movq 8(%rsp), %r10\n"
    "movq %r10, (%rax)\n"
    "addq $16, %rsp\n"
    "xorl %eax, %eax\n"
    ".Lvinix_vmx_return:\n"
    "addq $8, %rsp\n"
    "popq %r15\n"
    "popq %r14\n"
    "popq %r13\n"
    "popq %r12\n"
    "popq %rbx\n"
    "popq %rbp\n"
    "ret\n"
    ".size vinix_vmx_enter, .-vinix_vmx_enter\n"
);

#else

int vinix_vmx_on(uint64_t physical_address) { (void)physical_address; return -1; }
int vinix_vmx_off(void) { return -1; }
int vinix_vmx_clear(uint64_t physical_address) { (void)physical_address; return -1; }
int vinix_vmx_load(uint64_t physical_address) { (void)physical_address; return -1; }
int vinix_vmx_write(uint64_t field, uint64_t value) { (void)field; (void)value; return -1; }
int vinix_vmx_read(uint64_t field, uint64_t *value) { (void)field; (void)value; return -1; }
int vinix_vmx_enter(struct vinix_vmx_registers *registers) { (void)registers; return -1; }
void vinix_vmx_fxsave(void *state) { (void)state; }
void vinix_vmx_fxrstor(const void *state) { (void)state; }
void vinix_vmx_sgdt(struct vinix_vmx_descriptor *descriptor) { (void)descriptor; }
void vinix_vmx_sidt(struct vinix_vmx_descriptor *descriptor) { (void)descriptor; }
uint16_t vinix_vmx_read_cs(void) { return 0; }
uint16_t vinix_vmx_read_ss(void) { return 0; }
uint16_t vinix_vmx_read_ds(void) { return 0; }
uint16_t vinix_vmx_read_es(void) { return 0; }
uint16_t vinix_vmx_read_fs(void) { return 0; }
uint16_t vinix_vmx_read_gs(void) { return 0; }
uint16_t vinix_vmx_read_tr(void) { return 0; }

#endif
