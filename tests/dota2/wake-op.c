/* A controlled 4KiB x86 ELF layout on Vinix's 16KiB native pages.
 * smc_touch and smc_word occupy distinct target pages of one host page. */
extern long syscall(long, ...);
extern int printf(const char *, ...);
extern int fflush(void *);
extern int *__errno_location(void);
extern unsigned int alarm(unsigned int);
extern void _exit(int);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *);
extern int pthread_join(unsigned long, void **);
struct timespec { long sec, ns; };

static int failures;
static _Atomic int worker_started, worker_stop;
static _Atomic unsigned long worker_progress;
static _Atomic unsigned int worker_requested_step, worker_completed_step;
static unsigned int smc_word __attribute__((section(".smc_data"), aligned(4), used)) = 17;

static __attribute__((section(".smc_code"), noinline, used)) unsigned smc_touch(unsigned value)
{
    __asm__ volatile("" : "+r"(value));
    return value + 1;
}

static long call(long number, unsigned long a1, unsigned long a2,
                 unsigned long a3, unsigned long a4, unsigned long a5, unsigned long a6)
{
    return syscall(number, a1, a2, a3, a4, a5, a6);
}

static void check(int okay, const char *name)
{
    printf("WAKE-OP CHECK %s %s\n", name, okay ? "PASS" : "FAIL");
    fflush(0);
    if (!okay) ++failures;
}

static long wake_op(void *primary, void *secondary, unsigned int encoded)
{
    return call(202, (unsigned long)primary, 133, 1, 1,
                (unsigned long)secondary, encoded);
}

static void expect_error(void *primary, void *secondary, int expected, const char *name)
{
    long result = wake_op(primary, secondary, (23U << 12) | 17U);
    int error = result < 0 ? *__errno_location() : 0;
    printf("WAKE-OP ERROR %s result=%ld errno=%d expected=%d\n", name, result, error, expected);
    check(result == -1 && error == expected, name);
}

static void pause_ms(long ms)
{
    struct timespec time = {ms / 1000, ms % 1000 * 1000000};
    while (call(35, (unsigned long)&time, (unsigned long)&time, 0, 0, 0, 0))
        if (*__errno_location() != 4) _exit(81);
}

static unsigned long long now_ns(void)
{
    struct timespec time;
    if (call(228, 1, (unsigned long)&time, 0, 0, 0, 0)) _exit(86);
    return (unsigned long long)time.sec * 1000000000ULL + time.ns;
}

static void *code_worker(void *unused)
{
    (void)unused;
    unsigned long cpu = 2;
    if (call(203, 0, sizeof(cpu), (unsigned long)&cpu, 0, 0, 0)) _exit(82);
    worker_started = 1;
    unsigned value = 0;
    while (!worker_stop) {
        /* Read the requested generation before executing the protected code,
         * so its acknowledgement proves an execution after publication. */
        unsigned int step = worker_requested_step;
        value = smc_touch(value);
        ++worker_progress;
        if (step > worker_completed_step) worker_completed_step = step;
    }
    return 0;
}

__asm__(".text\n.global _start\n_start:\n"
        "xor %ebp,%ebp\nmov %rdx,%r9\npop %rsi\nmov %rsp,%rdx\n"
        "and $-16,%rsp\npush %rax\npush %rsp\nxor %r8d,%r8d\nxor %ecx,%ecx\n"
        "lea main(%rip),%rdi\ncall *__libc_start_main@GOTPCREL(%rip)\nhlt\n");

int main(void)
{
    alarm(30);
    unsigned long cpu = 1;
    check(call(203, 0, sizeof(cpu), (unsigned long)&cpu, 0, 0, 0) == 0, "reader-affinity");
    unsigned int *rw = (void *)call(9, 0, 16384, 3, 0x22, ~0UL, 0);
    unsigned int *protected = (void *)call(9, 0, 16384, 3, 0x22, ~0UL, 0);
    if (rw == (void *)-1 || protected == (void *)-1) _exit(83);
    *rw = *protected = 0;
    unsigned long code = (unsigned long)smc_touch, data = (unsigned long)&smc_word;
    printf("WAKE-OP LAYOUT code=0x%lx data=0x%lx host-page=0x%lx\n", code, data, code & ~16383UL);
    check((code & ~16383UL) == (data & ~16383UL) &&
          (code & ~4095UL) != (data & ~4095UL), "distinct-target-pages-share-native-page");

    /* Translating this function protects the native page containing smc_word.
     * No userspace write touches that word between this call and WAKE_OP. */
    check(smc_touch(7) == 8, "translated-code-runs");
    long result = wake_op(rw, &smc_word, (23U << 12) | 17U);
    int error = result < 0 ? *__errno_location() : 0;
    printf("WAKE-OP SMC result=%ld errno=%d word=%u\n", result, error, smc_word);
    check(result == 0 && smc_word == 23, "native-write-to-smc-protected-word");

    /* The other thread repeatedly translates code invalidated by each native
     * write. Its reprotection races the validation/syscall interval. Require
     * one acknowledged execution after every write: a fast parent loop alone
     * does not prove that the code thread ran during the measured cohort. */
    unsigned long worker;
    if (pthread_create(&worker, 0, code_worker, 0)) _exit(84);
    for (int i = 0; !worker_started && i < 2000; ++i) pause_ms(1);
    check(worker_started, "code-worker-started");
    pause_ms(20);
    unsigned long before = worker_progress;
    unsigned long long deadline = now_ns() + 15000000000ULL;
    int okay = 0, faults = 0, acknowledgements = 0;
    for (int i = 0; i < 128; ++i) {
        smc_touch((unsigned)i);
        result = wake_op(rw, &smc_word, (1U << 28) | (1U << 12));
        if (result == 0) ++okay;
        else if (*__errno_location() == 14) ++faults;
        /* WAKE_OP has returned before publication. Waiting here takes no
         * translator memory lock and lets the worker retranslate the code. */
        worker_requested_step = (unsigned int)i + 1;
        while (worker_completed_step < (unsigned int)i + 1 && now_ns() < deadline)
            pause_ms(1);
        if (worker_completed_step < (unsigned int)i + 1) break;
        ++acknowledgements;
    }
    unsigned long after = worker_progress;
    worker_stop = 1;
    if (pthread_join(worker, 0)) _exit(85);
    printf("WAKE-OP RACE iterations=128 okay=%d efault=%d word=%u progress=%lu,%lu acknowledgements=%d\n",
           okay, faults, smc_word, before, after, acknowledgements);
    check(okay == 128 && smc_word == 151, "native-writes-with-concurrent-code-execution");
    check(acknowledgements == 128, "code-worker-acknowledged-every-write");
    check(after > before, "code-worker-ran-during-native-writes");

    check(call(10, (unsigned long)protected, 16384, 2, 0, 0, 0) == 0, "make-write-only");
    check(wake_op(rw, protected, (29U << 12)) == 0, "write-only-secondary");
    check(call(10, (unsigned long)protected, 16384, 3, 0, 0, 0) == 0, "restore-readable");
    check(*protected == 29, "write-only-operation-stored-value");
    check(call(10, (unsigned long)protected, 16384, 1, 0, 0, 0) == 0, "make-read-only");
    check(call(202, (unsigned long)protected, 129, 1, 0, 0, 0) == 0, "read-only-primary-wake");
    check(wake_op(protected, rw, (23U << 12)) == 0 && *rw == 23, "read-only-primary-wake-op");
    expect_error(rw, protected, 14, "read-only-secondary");
    expect_error((char *)rw + 1, rw, 22, "misaligned-primary");
    expect_error(rw, (char *)rw + 1, 22, "misaligned-secondary");
    check(call(10, (unsigned long)protected, 16384, 0, 0, 0, 0) == 0, "make-prot-none");
    expect_error(rw, protected, 14, "prot-none-secondary");
    check(call(11, (unsigned long)protected, 16384, 0, 0, 0, 0) == 0, "unmap-secondary");
    expect_error(rw, protected, 14, "unmapped-secondary");
    check(call(11, (unsigned long)rw, 16384, 0, 0, 0, 0) == 0, "unmap-primary");
    printf("WAKE-OP %s failures=%d\n", failures ? "FAIL" : "PASS", failures);
    fflush(0);
    alarm(0);
    return failures ? 1 : 0;
}
