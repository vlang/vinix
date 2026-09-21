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
// V mangles a global/exported name as <module>__<name>, where <module> is
// whatever the file's own `module` statement says -- not its directory
// path. dev/serial/serial.v says `module serial`, so the real symbols are
// serial__out/serial__panic_out, not dev__serial__out/dev__serial__panic_out
// (this mismatch went unnoticed until a genuinely clean build actually
// needed to resolve it).
void serial__out(char);
void serial__panic_out(char);
#endif
void term__print(const char *, uint64_t);

static void _putchar(int character, void *extra_arg) {
    (void)character;
    (void)extra_arg;
#ifndef PROD
#ifdef __AARCH64__
    aarch64__uart__putc((uint8_t)character);
#else
    serial__out(character);
#endif
#endif
}

static void _putchar_panic(int character, void *extra_arg) {
    (void)extra_arg;
#ifndef PROD
#ifdef __AARCH64__
    aarch64__uart__putc((uint8_t)character);
#else
    serial__panic_out(character);
#endif
#endif
    term__print((char *)&character, 1);
}

// Same mangling mismatch as above: V emits struct methods as
// <module>__<Struct>__<method> (double underscore before the method name),
// and printf_lock itself lives in module kprint, not as a bare global.
void klock__Lock__acquire(void *);
void klock__Lock__release(void *);
extern char kprint__printf_lock;

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
    klock__Lock__acquire(&kprint__printf_lock);
    int ret = npf_vpprintf(_putchar, NULL, fmt, l);
    klock__Lock__release(&kprint__printf_lock);
    va_end(l);
    return ret;
#endif
}


int printf_panic(char *fmt, ...) {
    va_list l;
    va_start(l, fmt);
    int ret = npf_vpprintf(_putchar_panic, NULL, fmt, l);
    va_end(l);
    return ret;
}

// V's own generated code (v3_eprint_lit/v3_eprintln_string in the C backend,
// emitted for every `assert` statement's failure path) calls fprintf(stderr,
// ...) directly, unconditionally, with no target-specific override the way
// print/println have via term__print/dev.serial -- V 0.5.2's C backend has
// no freestanding hook for it. stderr is never dereferenced by this fprintf,
// only compared/passed around, so it just needs to be a non-null FILE*; an
// assertion failure is exactly the kind of diagnostic that must reach a real
// output, so this reuses printf_panic's unconditional, PROD-ungated path
// rather than the PROD-gated ordinary printf().
static struct __file _stderr_file;
FILE *stderr = &_stderr_file;

// Deliberately not routed through nanoprintf: this build compiles out
// NANOPRINTF_USE_PRECISION_FORMAT_SPECIFIERS, which "%.*s" (V's length-
// prefixed string format) needs, so nanoprintf would silently misparse it.
// V's C backend only ever emits two call shapes here -- "%s" for a NUL-
// terminated C string literal, "%.*s" for a length-prefixed V string, both
// followed by whatever literal text (e.g. "\n") the format string carries --
// so this handles exactly those instead of being a general fprintf.
int fprintf(FILE *restrict stream, const char *restrict fmt, ...) {
    (void)stream;
    va_list l;
    va_start(l, fmt);
    const char *rest = fmt;
    if (fmt[0] == '%' && fmt[1] == 's') {
        const char *s = va_arg(l, const char *);
        while (*s) {
            _putchar_panic((unsigned char)*s++, NULL);
        }
        rest = fmt + 2;
    } else if (fmt[0] == '%' && fmt[1] == '.' && fmt[2] == '*' && fmt[3] == 's') {
        int len = va_arg(l, int);
        const char *s = va_arg(l, const char *);
        for (int i = 0; i < len; i++) {
            _putchar_panic((unsigned char)s[i], NULL);
        }
        rest = fmt + 4;
    }
    while (*rest) {
        _putchar_panic((unsigned char)*rest++, NULL);
    }
    va_end(l);
    return 0;
}
