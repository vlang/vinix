#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

#include <printf/printf.h>

void dev__serial__out(char);
void dev__serial__panic_out(char);
void term__print(const char *, uint64_t);

static void _putchar(char character, void *extra_arg) {
    (void)character;
    (void)extra_arg;
#ifndef PROD
    dev__serial__out(character);
#endif
}

static void _putchar_panic(char character, void *extra_arg) {
    (void)extra_arg;
#ifndef PROD
    dev__serial__panic_out(character);
#endif
    term__print(&character, 1);
}

void klock__Lock_acquire(void *);
void klock__Lock_release(void *);
extern char printf_lock;

int printf(const char *restrict fmt, ...) {
    va_list l;
    va_start(l, fmt);
    klock__Lock_acquire(&printf_lock);
    int ret = vfctprintf(_putchar, NULL, fmt, l);
    klock__Lock_release(&printf_lock);
    va_end(l);
    return ret;
}

int printf_panic(const char *restrict fmt, ...) {
    va_list l;
    va_start(l, fmt);
    int ret = vfctprintf(_putchar_panic, NULL, fmt, l);
    va_end(l);
    return ret;
}
