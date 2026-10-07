/* Native libc declarations for the independent process dumpability fixture. */
#ifndef VINIX_DUMP_NATIVE_ABI_H
#define VINIX_DUMP_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/auxv.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>
typedef long vdu_native_long;
_Static_assert(sizeof(vdu_native_long) == 8 && sizeof(unsigned long) == 8,
               "native prctl and auxiliary-vector words");
_Static_assert(sizeof(pid_t) == 4 && sizeof(uid_t) == 4 && sizeof(gid_t) == 4,
               "native process and credential widths");
#endif
