/* Diagnostic for Valve's unmodified Linux libsteam_api.so and steamclient.
 * Link to the staged Bookworm libc directly; no host or musl CRT is used.
 * Prototypes suffice here, so staging development headers is unnecessary.
 */
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern char *dlerror(void);
extern int printf(const char *, ...);
extern int puts(const char *);
extern int fflush(void *);
extern int strcmp(const char *, const char *);
extern unsigned int sleep(unsigned int);
extern int backtrace(void **, int);
extern void backtrace_symbols_fd(void *const *, int, int);
extern void _exit(int);
typedef void (*signal_handler)(int);
extern signal_handler signal(int, signal_handler);
struct library_origin {
    const char *filename;
    void *base;
    const char *symbol;
    void *address;
};
extern int dladdr(const void *, struct library_origin *);

__asm__(".text\n"
        ".global _start\n"
        "_start:\n"
        "xor %ebp,%ebp\n"
        "mov %rdx,%r9\n"
        "pop %rsi\n"
        "mov %rsp,%rdx\n"
        "and $-16,%rsp\n"
        "push %rax\n"
        "push %rsp\n"
        "xor %r8d,%r8d\n"
        "xor %ecx,%ecx\n"
        "lea main(%rip),%rdi\n"
        "call *__libc_start_main@GOTPCREL(%rip)\n"
        "hlt\n");

static void failure(int number)
{
    void *frames[32];
    printf("VINIX-DOTA2-STEAM-SMOKE-SIGNAL: %d\n", number);
    fflush((void *)0);
    /* This test-only crash diagnostic may invoke libc's lazy unwinder. */
    int count = backtrace(frames, 32);
    backtrace_symbols_fd(frames, count, 2);
    _exit(128 + number);
}

static void coroutine_origins(void)
{
    const char *names[] = {"Coroutine_Continue", "Coroutine_Create",
                          "Coroutine_IsActive", "Coroutine_YieldToMain"};
    for (unsigned int index = 0; index < sizeof names / sizeof names[0]; ++index) {
        void *address = dlsym((void *)0, names[index]); /* RTLD_DEFAULT */
        struct library_origin origin = {0};
        const char *filename = address && dladdr(address, &origin) ?
            origin.filename : "unavailable";
        printf("VINIX-DOTA2-STEAM-SMOKE-COROUTINE: %s address=%p library=%s\n",
               names[index], address, filename);
    }
    fflush((void *)0);
}

int main(int argc, char **argv)
{
    signal(11, failure);
    signal(6, failure);
    if (argc < 2) {
        puts("usage: steam-smoke /path/to/actual/libsteam_api.so [anonymous|safe|safe-anonymous|load] [actual/libtier0.so]");
        return 2;
    }
    if (argc > 3) {
        printf("VINIX-DOTA2-STEAM-SMOKE-TIER0-DLOPEN: %s\n", argv[3]);
        fflush((void *)0);
        if (!dlopen(argv[3], 2 | 0x100)) { /* RTLD_NOW | RTLD_GLOBAL */
            printf("VINIX-DOTA2-STEAM-SMOKE-TIER0-FAIL: %s\n", dlerror());
            return 7;
        }
        puts("VINIX-DOTA2-STEAM-SMOKE-TIER0-LOADED");
        coroutine_origins();
    }
    printf("VINIX-DOTA2-STEAM-SMOKE-DLOPEN: %s\n", argv[1]);
    fflush((void *)0);
    void *library = dlopen(argv[1], 2); /* RTLD_NOW */
    if (!library) {
        printf("VINIX-DOTA2-STEAM-SMOKE-DLOPEN-FAIL: %s\n", dlerror());
        return 3;
    }
    if (argc > 2 && !strcmp(argv[2], "load")) {
        puts("VINIX-DOTA2-STEAM-SMOKE-LOAD-PASS");
        return 0;
    }
    const char *name = argc > 2 && !strcmp(argv[2], "safe") ?
        "SteamAPI_InitSafe" : "SteamAPI_InitAnonymousUser";
    unsigned char (*initialize)(void) = (unsigned char (*)(void))dlsym(library, name);
    void (*shutdown)(void) = (void (*)(void))dlsym(library, "SteamAPI_Shutdown");
    void (*callbacks)(void) = (void (*)(void))dlsym(library, "SteamAPI_RunCallbacks");
    if (!initialize || !shutdown || !callbacks) {
        printf("VINIX-DOTA2-STEAM-SMOKE-SYMBOL-FAIL: %s\n", dlerror());
        return 4;
    }
    if (argc > 2 && !strcmp(argv[2], "safe-anonymous")) {
        unsigned char (*safe)(void) = (unsigned char (*)(void))dlsym(library, "SteamAPI_InitSafe");
        if (!safe) {
            printf("VINIX-DOTA2-STEAM-SMOKE-SYMBOL-FAIL: %s\n", dlerror());
            return 4;
        }
        puts("VINIX-DOTA2-STEAM-SMOKE-CALL: SteamAPI_InitSafe");
        fflush((void *)0);
        unsigned char normal = safe();
        printf("VINIX-DOTA2-STEAM-SMOKE-SAFE-RETURN: %u\n", (unsigned int)normal);
        fflush((void *)0);
        if (normal) {
            shutdown();
            puts("VINIX-DOTA2-STEAM-SMOKE-UNEXPECTED-CLIENT");
            return 6;
        }
    }
    printf("VINIX-DOTA2-STEAM-SMOKE-CALL: %s\n", name);
    fflush((void *)0);
    unsigned char result = initialize();
    printf("VINIX-DOTA2-STEAM-SMOKE-RETURN: %u\n", (unsigned int)result);
    fflush((void *)0);
    if (argc > 3)
        coroutine_origins();
    if (!result)
        return 5;
    callbacks();
    sleep(2);
    callbacks();
    puts("VINIX-DOTA2-STEAM-SMOKE-SHUTDOWN");
    fflush((void *)0);
    shutdown();
    puts("VINIX-DOTA2-STEAM-SMOKE-PASS");
    return 0;
}
