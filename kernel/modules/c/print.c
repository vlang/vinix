#include <stdarg.h>
#include <stddef.h>

int printf(const char *format, ...) {
    (void)format;
    return -1;
}

int vsprintf(char *buffer, const char *format, va_list vlist) {
    (void)buffer;
    (void)format;
    (void)vlist;
    return -1;
}

int vsnprintf(char *restrict buffer, size_t bufsz, const char *restrict format, va_list vlist) {
    (void)buffer;
    (void)bufsz;
    (void)format;
    (void)vlist;
    return -1;
}
