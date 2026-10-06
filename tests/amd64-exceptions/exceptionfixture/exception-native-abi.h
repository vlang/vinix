#ifndef VINIX_EXCEPTION_FIXTURE_NATIVE_ABI_H
#define VINIX_EXCEPTION_FIXTURE_NATIVE_ABI_H
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <ucontext.h>
#include <unistd.h>
_Static_assert(sizeof(greg_t) == 8, "native RIP width");
_Static_assert(__builtin_types_compatible_p(greg_t, long long), "native greg_t representation");
_Static_assert(sizeof(((mcontext_t *)0)->gregs) / sizeof(greg_t) == 23, "native register bank");
_Static_assert(sizeof(unsigned int) == 4, "native atomic width");
#endif
