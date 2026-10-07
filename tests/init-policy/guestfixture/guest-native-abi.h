/* SPDX-License-Identifier: GPL-2.0-only */
/* Native declarations and the original volatile signal word view only. */
#ifndef VINIX_INIT_POLICY_GUEST_NATIVE_ABI_H
#define VINIX_INIT_POLICY_GUEST_NATIVE_ABI_H
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
struct vinix_init_guest_signal_word { volatile sig_atomic_t value; };
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4 &&
    __builtin_types_compatible_p(pid_t, int), "native process and descriptor words");
_Static_assert(sizeof(sig_atomic_t) == 4 && sizeof(struct vinix_init_guest_signal_word) == 4 &&
    _Alignof(struct vinix_init_guest_signal_word) == _Alignof(sig_atomic_t) &&
    offsetof(struct vinix_init_guest_signal_word, value) == 0, "native volatile signal word");
_Static_assert(sizeof(size_t) == 8 && sizeof(ssize_t) == 8 &&
    __builtin_types_compatible_p(ssize_t, ptrdiff_t), "native guest transfer counts");
#endif
