/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native syscall/stdio ABI bindings; policy and parsing are V. */
#define _GNU_SOURCE
#include "mac.h"
#include "mac_v.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#ifndef VINIX_MAC_HOST_TEST
#include <sys/prctl.h>
#include <sys/xattr.h>
#endif
#include <unistd.h>
_Static_assert(VINIX_MAC_DOMAINS == 16 && VINIX_MAC_TYPES == 32 && VINIX_MAC_LABEL_TYPES == 29
               && VINIX_MAC_ALL == 511, "V mandatory policy ABI constants");
int64_t vm_prctl(uint64_t command, uint64_t domain, uint64_t kind, uint64_t mask) {
    return prctl(VINIX_MAC_PRCTL, (unsigned long)command, (unsigned long)domain,
                 (unsigned long)kind, (unsigned long)mask);
}
int vm_lsetxattr(const char *path, const char *name, const void *value, size_t length, int flags) {
    return lsetxattr(path, name, value, length, flags);
}
int vm_execvp(const char *path, char **argv) { return execvp(path, argv); }
void vm_error(const char *operation) { fprintf(stderr, "vinix-mac: %s: %s\n", operation, strerror(errno)); }
void vm_usage(const char *text) { fputs(text, stderr); }
void vm_status(int64_t domain, int64_t sealed) { printf("domain=%ld sealed=%ld\n", (long)domain, (long)sealed); }
#ifdef main
static inline int number(const char *text, unsigned limit, unsigned *value) { return vm_number(text, limit, value); }
static inline int permissions(const char *text, unsigned *mask) { return vm_permissions(text, mask); }
#endif
int main(int argc, char **argv) { return vm_main(argc, argv); }
