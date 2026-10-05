/* Load/close/reload an unmodified Linux library independently of Steam.
 * Link this header-free x86-64 probe to the staged glibc, like steam-smoke.c.
 * Bookworm libnm stores its literal strings in resident GLib state: its
 * second ordinary load faults on both Vinix and native x86 Linux, whereas
 * RTLD_NODELETE preserves the library and all three cycles succeed.
 */
extern void *dlopen(const char *, int);
extern void *dlmopen(long, const char *, int);
extern int dlclose(void *);
extern char *dlerror(void);
extern int printf(const char *, ...);
extern int puts(const char *);
extern int fflush(void *);
extern int strcmp(const char *, const char *);
extern int backtrace(void **, int);
extern void backtrace_symbols_fd(void *const *, int, int);
extern void _exit(int);
typedef void (*signal_handler)(int);
extern signal_handler signal(int, signal_handler);

__asm__(".text\n.global _start\n_start:\n"
        "xor %ebp,%ebp\nmov %rdx,%r9\npop %rsi\nmov %rsp,%rdx\n"
        "and $-16,%rsp\npush %rax\npush %rsp\nxor %r8d,%r8d\n"
        "xor %ecx,%ecx\nlea main(%rip),%rdi\n"
        "call *__libc_start_main@GOTPCREL(%rip)\nhlt\n");

static void failure(int number)
{
    void *frames[32];
    printf("VINIX-DOTA2-LOADER-SIGNAL: %d\n", number);
    fflush((void *)0);
    /* Test-only diagnostics; libc may lazily load its unwinder here. */
    int count = backtrace(frames, 32);
    backtrace_symbols_fd(frames, count, 2);
    _exit(128 + number);
}

int main(int argc, char **argv)
{
    if (argc != 3 || (strcmp(argv[2], "dlopen") && strcmp(argv[2], "base") &&
                     strcmp(argv[2], "new") && strcmp(argv[2], "nodelete"))) {
        puts("usage: library-loader /path/to/library.so dlopen|base|new|nodelete");
        return 2;
    }
    signal(11, failure);
    signal(6, failure);
    int base = !strcmp(argv[2], "base");
    int fresh = !strcmp(argv[2], "new");
    int flags = 2 | (!strcmp(argv[2], "nodelete") ? 0x1000 : 0); /* NOW, NODELETE */
    for (int iteration = 1; iteration <= 3; iteration++) {
        printf("VINIX-DOTA2-LOADER-OPEN: %s %d\n", argv[2], iteration);
        fflush((void *)0);
        void *library = (base || fresh) ?
            dlmopen(fresh ? -1L : 0L, argv[1], flags) : dlopen(argv[1], flags);
        if (!library) {
            printf("VINIX-DOTA2-LOADER-ERROR: %s\n", dlerror());
            return 3;
        }
        int result = dlclose(library);
        printf("VINIX-DOTA2-LOADER-CLOSE: %d\n", result);
        fflush((void *)0);
        if (result)
            return 4;
    }
    puts("VINIX-DOTA2-LOADER-PASS");
    return 0;
}
