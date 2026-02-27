#ifndef _SYMBOLS_H
#define _SYMBOLS_H

extern char text_start[];
extern char text_end[];
extern char rodata_start[];
extern char rodata_end[];
extern char data_start[];
extern char data_end[];

extern char interrupt_thunks[];

/* AArch64 assembly symbols */
extern void exception_vectors(void);
extern void sched_switch_context(void *gpr_state, unsigned long kernel_stack);
extern void yield_dispatch(void *handler_fn_ptr);

/* Helper to call a void function pointer (breaks circular import deps) */
static inline void vinix_call_void_fn(void *fn) {
    ((void (*)(void))fn)();
}

/* Read current SP (V's inline asm can't handle sp register) */
static inline unsigned long read_current_sp(void) {
    unsigned long sp;
    __asm__ volatile("mov %0, sp" : "=r"(sp));
    return sp;
}

/* Debug: trace syscall number via UART */
void aarch64__uart__putc(unsigned char c);
static inline void trace_syscall_nr(unsigned long nr) {
    aarch64__uart__putc('S');
    aarch64__uart__putc('C');
    aarch64__uart__putc(':');
    /* Print number in decimal */
    char buf[8];
    int i = 0;
    if (nr == 0) { buf[i++] = '0'; }
    else {
        unsigned long n = nr;
        while (n > 0 && i < 7) { buf[i++] = '0' + (n % 10); n /= 10; }
    }
    while (--i >= 0) aarch64__uart__putc(buf[i]);
    aarch64__uart__putc(' ');
}

#endif
