#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

#define NANOPRINTF_IMPLEMENTATION
#define NANOPRINTF_USE_FIELD_WIDTH_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_PRECISION_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_FLOAT_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_LARGE_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_BINARY_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_WRITEBACK_FORMAT_SPECIFIERS 1
#include <nanoprintf.h>

void dev__serial__out(char);
void dev__serial__panic_out(char);
void term__print(const char *, uint64_t);

static void _putchar(int character, void *extra_arg) {
    (void)character;
    (void)extra_arg;
#ifndef PROD
    dev__serial__out(character);
#endif
}

static void _putchar_panic(int character, void *extra_arg) {
    (void)extra_arg;
#ifndef PROD
    dev__serial__panic_out(character);
#endif
    term__print((char *)&character, 1);
}

void klock__Lock_acquire(void *);
void klock__Lock_release(void *);
extern char printf_lock;

int printf(const char *restrict fmt, ...) {
    va_list l;
    va_start(l, fmt);
    klock__Lock_acquire(&printf_lock);
    int ret = npf_vpprintf(_putchar, NULL, fmt, l);
    klock__Lock_release(&printf_lock);
    va_end(l);
    return ret;
}

int printf_panic(const char *restrict fmt, ...) {
    va_list l;
    va_start(l, fmt);
    int ret = npf_vpprintf(_putchar_panic, NULL, fmt, l);
    va_end(l);
    return ret;
}
