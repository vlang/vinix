/* Native declarations for the independent listen backlog regression. */
#ifndef VINIX_BACKLOG_NATIVE_ABI_H
#define VINIX_BACKLOG_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
typedef unsigned long long vlb_native_ull;
enum { VLB_PATH_OFFSET = offsetof(struct sockaddr_un, sun_path) };
_Static_assert(sizeof(int) == 4 && sizeof(short) == 2, "native syscall integers");
_Static_assert(sizeof(long) == 8 && sizeof(vlb_native_ull) == 8, "native syscall words");
_Static_assert(sizeof(((struct sockaddr_un *)0)->sun_path) == 108, "native UNIX pathname");
_Static_assert(sizeof(socklen_t) == 4, "native socket length");
_Static_assert(INT_MIN == (-2147483647 - 1) && INT_MAX == 2147483647, "native int boundaries");
#endif
