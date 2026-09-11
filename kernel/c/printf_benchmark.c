#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>

#include <nanoprintf.h>

#ifdef __AARCH64__
void aarch64__uart__putc(uint8_t c);
#else
void dev__serial__panic_out(char c);
#endif

// The opt-in allocator benchmark runs before the scheduler and needs the same
// serial records in debug and production builds. Keep this separate from
// printf()/printf_panic(), whose production silence is a kernel policy.
static void _putchar_benchmark(int character, void *extra_arg) {
    (void)extra_arg;
#ifdef __AARCH64__
    aarch64__uart__putc((uint8_t)character);
#else
    dev__serial__panic_out((char)character);
#endif
}

int printf_benchmark(const char *restrict fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int ret = npf_vpprintf(_putchar_benchmark, NULL, fmt, args);
    va_end(args);
    return ret;
}
