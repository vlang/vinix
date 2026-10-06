/* Native musl declarations; the poll regression is maintained in V. */
#ifndef VINIX_POLL_NATIVE_ABI_H
#define VINIX_POLL_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
_Static_assert(sizeof(nfds_t) == 8, "native poll count");
_Static_assert(sizeof(struct pollfd) == 8, "native pollfd layout");
_Static_assert(sizeof(pid_t) == 4 && sizeof(int) == 4, "native syscall integers");
#endif
