// stdio.h: Standard I/O function definitions.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

#ifndef _STDIO_H
#define _STDIO_H

#include <stdarg.h>
#include <stddef.h>

struct __file {
    void *ptr;
};

typedef struct __file FILE;

int printf(const char* format, ...);
int printf_panic(const char* format, ...);
int sprintf(char* buffer, const char* format, ...);
int snprintf(char* buffer, size_t count, const char* format, ...);
int vprintf(const char* format, va_list va);
int vsnprintf(char* buffer, size_t count, const char* format, va_list va);
int fctprintf(void (*out)(char character, void* arg), void* arg, const char* format, ...);

#endif
