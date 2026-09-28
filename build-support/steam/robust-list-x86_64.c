/* QEMU linux-user accepts set_robust_list but does not answer
 * get_robust_list. Steam's 64-bit web helper calls glibc's syscall() to
 * inspect the current thread and deliberately crashes if the head is absent.
 *
 * Debian Bookworm's x86-64 glibc 2.36 registers pthread_self() + 0x2e0
 * with a 24-byte head. Keep this preload specific to translated x86-64
 * programs; the i386 client has a different pthread layout. */

extern void *dlsym(void *, const char *);
extern void *pthread_self(void);

typedef long (*syscall_function)(long, ...);

long syscall(long number, ...) {
    __builtin_va_list arguments;
    __builtin_va_start(arguments, number);
    long a1 = __builtin_va_arg(arguments, long);
    long a2 = __builtin_va_arg(arguments, long);
    long a3 = __builtin_va_arg(arguments, long);
    long a4 = __builtin_va_arg(arguments, long);
    long a5 = __builtin_va_arg(arguments, long);
    long a6 = __builtin_va_arg(arguments, long);
    __builtin_va_end(arguments);

    /* __NR_get_robust_list for Linux/x86-64, current thread only. */
    if (number == 274 && a1 == 0 && a2 != 0 && a3 != 0) {
        *(void **)a2 = (char *)pthread_self() + 0x2e0;
        *(unsigned long *)a3 = 24;
        return 0;
    }

    syscall_function next = (syscall_function)dlsym((void *)-1, "syscall");
    return next(number, a1, a2, a3, a4, a5, a6);
}
