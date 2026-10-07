/* Native declarations and widths only; protection and cache-walk policy are V. */
#ifndef VINIX_EXECUTE_ONLY_NATIVE_ABI_H
#define VINIX_EXECUTE_ONLY_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
typedef struct { volatile unsigned char value; } exec_volatile_byte;
#if defined(__aarch64__) && !defined(EXECUTE_ONLY_EXPECT_READABLE)
#define EXEC_NATIVE_XONLY 1
#else
#define EXEC_NATIVE_XONLY 0
#endif
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4 && sizeof(long) == 8 &&
               sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && sizeof(off_t) == 8 &&
               sizeof(uintptr_t) == 8 && sizeof(exec_volatile_byte) == 1,
               "native process, mapping, transfer and volatile-read widths");
#endif
