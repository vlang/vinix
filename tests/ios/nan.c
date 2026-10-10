// SPDX-License-Identifier: GPL-2.0-or-later
// Bit patterns measured from the installed Darwin library. Volatile pointers
// ensure the compiler calls the library rather than folding its own NaN.
extern double nan(const char *);
extern float nanf(const char *);
extern int *__error(void);
extern int puts(const char *), printf(const char *, ...);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *);
extern int pthread_join(unsigned long, void **);

static double (*volatile call_nan)(const char *) = nan;
static float (*volatile call_nanf)(const char *) = nanf;
struct payload_case { const char *tag; unsigned long long wide; unsigned narrow; };
static const struct payload_case cases[] = {
    {"", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"1", 0x7ff8000000000001ULL, 0x7fc00001U},
    {"2", 0x7ff8000000000002ULL, 0x7fc00002U},
    {"42", 0x7ff800000000002aULL, 0x7fc0002aU},
    {"123", 0x7ff800000000007bULL, 0x7fc0007bU},
    {"0x1", 0x7ff8000000000001ULL, 0x7fc00001U},
    {"0Xabcdef", 0x7ff8000000abcdefULL, 0x7febcdefU},
    {"0x", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"077", 0x7ff800000000003fULL, 0x7fc0003fU},
    {"08", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"09", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"-1", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"+1", 0x7ff8000000000000ULL, 0x7fc00000U},
    {" 1", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"1 ", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"1z", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"a", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"beef", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0xdeadbeef", 0x7ff80000deadbeefULL, 0x7fedbeefU},
    {"(1)", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0x7ffffffffffff", 0x7fffffffffffffffULL, 0x7fffffffU},
    {"0x8000000000000", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0xfffffffffffff", 0x7fffffffffffffffULL, 0x7fffffffU},
    {"0x10000000000000", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0xffffffffffffffff", 0x7fffffffffffffffULL, 0x7fffffffU},
    {"0x10000000000000000", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0x10000000000000001", 0x7ff8000000000001ULL, 0x7fc00001U},
    {"0x123456789abcdef0123456789", 0x7ffdef0123456789ULL, 0x7fc56789U},
    {"18446744073709551617", 0x7ff8000000000001ULL, 0x7fc00001U},
    {"36893488147419103234", 0x7ff8000000000002ULL, 0x7fc00002U},
    {"00x1", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0X1234567z", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0x1p1", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"\t1", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"123456789012345678901234567890", 0x7ffbe0ee4e3f0ad2ULL, 0x7fff0ad2U},
    {"18446744073709551615", 0x7fffffffffffffffULL, 0x7fffffffU},
    {"18446744073709551616", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"0000000000000000000000000000000000000001", 0x7ff8000000000001ULL, 0x7fc00001U},
    {"0000000000000000000000000000000000000009", 0x7ff8000000000000ULL, 0x7fc00000U},
    {"999999999999999999999999999999999999999999999999999999999", 0x7fffffffffffffffULL, 0x7fffffffU},
};

static int check(void) {
    unsigned long long saved_status, saved_control;
    __asm__ volatile("mrs %0, fpsr" : "=r"(saved_status) : : "memory");
    __asm__ volatile("mrs %0, fpcr" : "=r"(saved_control) : : "memory");
    const unsigned presets[] = {0, 1, 8, 16};
    for (unsigned mode = 0; mode < 4; mode++) {
        unsigned long long control = (saved_control & ~(3ULL << 22)) | ((unsigned long long)mode << 22);
        __asm__ volatile("msr fpcr, %0" : : "r"(control) : "memory");
        for (unsigned i = 0; i < sizeof cases / sizeof *cases; i++) {
            unsigned long long expected = (saved_status & ~0x9fULL) | presets[mode], actual, actual_control;
            *__error() = 177;
            __asm__ volatile("msr fpsr, %0" : : "r"(expected) : "memory");
            union { double value; unsigned long long bits; } wide = {call_nan(cases[i].tag)};
            __asm__ volatile("mrs %0, fpsr" : "=r"(actual) : : "memory");
            __asm__ volatile("mrs %0, fpcr" : "=r"(actual_control) : : "memory");
            int error = *__error();
            if (wide.bits != cases[i].wide || error != 177 || actual != expected || actual_control != control) {
                __asm__ volatile("msr fpsr, %0" : : "r"(saved_status) : "memory");
                __asm__ volatile("msr fpcr, %0" : : "r"(saved_control) : "memory");
                printf("IOS-NAN: double case %u mode %u bits %llx errno %d status %llx control %llx\n",
                    i, mode, wide.bits, error, actual, actual_control);
                return 1;
            }
            *__error() = 178;
            __asm__ volatile("msr fpsr, %0" : : "r"(expected) : "memory");
            union { float value; unsigned bits; } narrow = {call_nanf(cases[i].tag)};
            __asm__ volatile("mrs %0, fpsr" : "=r"(actual) : : "memory");
            __asm__ volatile("mrs %0, fpcr" : "=r"(actual_control) : : "memory");
            error = *__error();
            if (narrow.bits != cases[i].narrow || error != 178 || actual != expected || actual_control != control) {
                __asm__ volatile("msr fpsr, %0" : : "r"(saved_status) : "memory");
                __asm__ volatile("msr fpcr, %0" : : "r"(saved_control) : "memory");
                printf("IOS-NAN: float case %u mode %u bits %x errno %d status %llx control %llx\n",
                    i, mode, narrow.bits, error, actual, actual_control);
                return 2;
            }
        }
    }
    __asm__ volatile("msr fpsr, %0" : : "r"(saved_status) : "memory");
    __asm__ volatile("msr fpcr, %0" : : "r"(saved_control) : "memory");
    return 0;
}

static void *worker(void *argument) {
    int *error = argument;
    for (int i = 0; i < 200 && !*error; i++) *error = check();
    return 0;
}

int main(void) {
    int error = check();
    if (error) return error;
    unsigned long threads[8]; int errors[8] = {0}, started = 0, failed = 0;
    *__error() = 12345;
    for (int i = 0; i < 8; i++) {
        if (pthread_create(&threads[i], 0, worker, &errors[i])) break;
        started++;
    }
    // Join every started worker even if creation or a prior worker failed.
    for (int i = 0; i < started; i++) if (pthread_join(threads[i], 0) || errors[i]) failed = 1;
    if (started != 8 || failed || *__error() != 12345) return 3;
    puts("IOS-NAN: decimal/octal/hex payloads, overflow, malformed tags, errno, floating state and eight threads");
    return 0;
}
