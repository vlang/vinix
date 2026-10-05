#ifndef _STDIO_H
#define _STDIO_H

#include <stdarg.h>
#include <stddef.h>

struct __file {
    void *ptr;
};

typedef struct __file FILE;

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

int printf(const char *restrict format, ...);
int snprintf(char *restrict str, size_t size, const char *restrict format, ...);
int fprintf(FILE *restrict stream, const char *restrict format, ...);
int printf_panic(char *format, ...);
int printf_benchmark(const char *restrict format, ...);

#endif
