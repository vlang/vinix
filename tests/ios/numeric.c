// SPDX-License-Identifier: GPL-2.0-or-later
// Identical calls run against the installed Mac library and the V adapters.
extern double atof(const char *);
extern long long atoll(const char *);
extern int *__error(void);
extern int puts(const char *), printf(const char *, ...);
extern int pthread_create(unsigned long *, const void *, void *(*)(void *), void *);
extern int pthread_join(unsigned long, void **);

struct floating_case { const char *text; unsigned long long bits; int error; };
static const struct floating_case floats[] = {
    {"", 0, 177}, {" \t", 0, 177}, {"bad", 0, 177}, {".x", 0, 177},
    {"-0", 0x8000000000000000ull, 177}, {"3.25", 0x400a000000000000ull, 177},
    {"  -12.5e2tail", 0xc093880000000000ull, 177}, {"0x1.8p+2", 0x4018000000000000ull, 177},
    {"nan", 0x7ff8000000000000ull, 177}, {"inf", 0x7ff0000000000000ull, 177},
    {"1e5000", 0x7ff0000000000000ull, 34}, {"1e-5000", 0, 34},
    {"4.9406564584124654e-324", 1, 34}, {"0x1p-1074", 1, 177},
    {"-0x1p-1074", 0x8000000000000001ull, 177},
    {"0x0.fffffffffffffp-1022", 0x000fffffffffffffull, 177},
    {"0x1.fffffffffffffp-1023", 0x0010000000000000ull, 177},
    {"0x1p-1075", 0, 34}, {"0x1.8p-1074", 2, 34},
    {"0x1.1p-1074", 1, 34}, {"0x1p-2000", 0, 34},
    {"0x1p+2000", 0x7ff0000000000000ull, 34},
    {"0x1p-1022", 0x0010000000000000ull, 177}, {"0e-9999", 0, 177},
    {"-0e9999", 0x8000000000000000ull, 177},
    // Exactly representable decimal minimum subnormal still reports ERANGE.
    {"4.940656458412465441765687928682213723650598026143247644255856825006755072702087"
     "51865299836361635992379796564695445717730926656710355939796398774796010781878126"
     "30071319031140452784581716784898210368871863605699873072305000638740915356498438"
     "73124733972731696151400317153853980741262385655911710266585566867681870395603106"
     "24931945271591492455329305456544401127480129709999541931989409080416563324524757"
     "14786901472678015935523861155013480352649347201937902681071074917033322268447533"
     "35720832431936092382893458368060106011506169809753078342277318329247904982524730"
     "77637592724787465608477820373446969953364701797267771758512566055119913150489110"
     "14510378627381672509558373897335989936648099411642057026370902792427675445652290"
     "87538682506419718265533447265625E-324", 1, 34},
};
struct integer_case { const char *text; long long value; int error; };
static const struct integer_case integers[] = {
    {"", 0, 22}, {" \t", 0, 22}, {"bad", 0, 22}, {"+x", 0, 22},
    {"-0", 0, 177}, {"3.25", 3, 177}, {"  -12.5e2tail", -12, 177},
    {"0x123", 0, 177}, {"9223372036854775807", 9223372036854775807ll, 177},
    {"-9223372036854775808", (-9223372036854775807ll - 1), 177},
    {"9223372036854775808", 9223372036854775807ll, 34},
    {"-9223372036854775809", (-9223372036854775807ll - 1), 34},
};
static int floating_environment(void) {
#if defined(__aarch64__) || defined(__arm64__)
    // Read ARM64 state directly so the same fixture can verify the adapter
    // without requiring any additional imported Darwin fenv services.
    unsigned long long saved;
    __asm__ volatile("mrs %0, fpsr" : "=r"(saved) : : "memory");
    const unsigned presets[] = {0, 1, 8, 16};
    const char *inputs[] = {"1e5000", "4.9406564584124654e-324", "0x1.8p-1074", "3.25", "bad"};
    for (unsigned i = 0; i < sizeof presets / sizeof *presets; i++) {
        for (unsigned j = 0; j < sizeof inputs / sizeof *inputs; j++) {
            unsigned long long expected = (saved & ~0x9full) | presets[i], actual;
            __asm__ volatile("msr fpsr, %0" : : "r"(expected) : "memory");
            volatile double value = atof(inputs[j]); (void)value;
            __asm__ volatile("mrs %0, fpsr" : "=r"(actual) : : "memory");
            __asm__ volatile("msr fpsr, %0" : : "r"(saved) : "memory");
            if (actual != expected) {
                printf("IOS-NUMERIC: fenv case %u/%u actual %llx expected %llx\n", i, j, actual, expected);
                return 15;
            }
        }
    }
#endif
    return 0;
}
static int check(void) {
    for (unsigned i = 0; i < sizeof floats / sizeof *floats; i++) {
        *__error() = 177;
        union { double value; unsigned long long bits; } actual = {atof(floats[i].text)};
        if (actual.bits != floats[i].bits || *__error() != floats[i].error) {
            printf("IOS-NUMERIC: atof case %u bits %llx errno %d\n", i, actual.bits, *__error());
            return 10;
        }
    }
    for (unsigned i = 0; i < sizeof integers / sizeof *integers; i++) {
        *__error() = 177;
        long long actual = atoll(integers[i].text);
        if (actual != integers[i].value || *__error() != integers[i].error) {
            printf("IOS-NUMERIC: atoll case %u value %lld errno %d\n", i, actual, *__error());
            return 11;
        }
    }
    return floating_environment();
}
static void *worker(void *argument) {
    int *error = argument;
    for (int i = 0; i < 200 && !*error; i++) *error = check();
    return 0;
}
int main(void) {
    int result = check();
    if (result) return result;
    unsigned long threads[8]; int errors[8] = {0};
    *__error() = 12345;
    for (int i = 0; i < 8; i++) if (pthread_create(&threads[i], 0, worker, &errors[i])) return 12;
    for (int i = 0; i < 8; i++) if (pthread_join(threads[i], 0) || errors[i]) return 13;
    if (*__error() != 12345) return 14;
    puts("IOS-NUMERIC: decimal/hex floats, signed zero, subnormals, integer limits and eight-thread errno/fenv");
    return 0;
}
