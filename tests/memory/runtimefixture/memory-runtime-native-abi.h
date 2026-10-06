/* Native SDK and production memory ABI declarations; checking algorithms are V. */
#ifndef VINIX_MEMORY_RUNTIME_NATIVE_ABI_H
#define VINIX_MEMORY_RUNTIME_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
void *vinix_memcpy(void *restrict, const void *restrict, size_t);
void *vinix_memset(void *, int, size_t);
void *vinix_memmove(void *, const void *, size_t);
int vinix_memcmp(const void *, const void *, size_t);
int vinix_atoi(const char *);
#endif
