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

#ifdef __AARCH64__
void aarch64__uart__putc(uint8_t c);
#else
void dev__serial__out(char);
void dev__serial__panic_out(char);
#endif
void term__print(const char *, uint64_t);

static void _putchar(int character, void *extra_arg) {
    (void)character;
    (void)extra_arg;
#ifndef PROD
#ifdef __AARCH64__
    aarch64__uart__putc((uint8_t)character);
#else
    dev__serial__out(character);
#endif
#endif
}

static void _putchar_panic(int character, void *extra_arg) {
    (void)extra_arg;
#ifndef PROD
#ifdef __AARCH64__
    aarch64__uart__putc((uint8_t)character);
#else
    dev__serial__panic_out(character);
#endif
#endif
    term__print((char *)&character, 1);
}

void klock__Lock_acquire(void *);
void klock__Lock_release(void *);
extern char printf_lock;

int printf(const char *restrict fmt, ...) {
#ifdef PROD
    // In PROD builds, _putchar is a no-op, so skip formatting entirely.
    // This avoids acquiring printf_lock which can deadlock when called
    // from syscall handlers with interrupts disabled.
    (void)fmt;
    return 0;
#else
    va_list l;
    va_start(l, fmt);
    klock__Lock_acquire(&printf_lock);
    int ret = npf_vpprintf(_putchar, NULL, fmt, l);
    klock__Lock_release(&printf_lock);
    va_end(l);
    return ret;
#endif
}


int printf_panic(const char *restrict fmt, ...) {
    va_list l;
    va_start(l, fmt);
    int ret = npf_vpprintf(_putchar_panic, NULL, fmt, l);
    va_end(l);
    return ret;
}
