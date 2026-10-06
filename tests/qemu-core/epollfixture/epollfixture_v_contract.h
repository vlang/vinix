/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_EPOLL_FIXTURE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_EPOLL_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#if defined(__APPLE__)
/* Import the unchanged Linux epoll declaration header with host-owned sigset_t. */
#include <signal.h>
#define __DEFINED_sigset_t
#endif
#include <sys/epoll.h>
_Static_assert(sizeof(int)==4 && sizeof(epoll_data_t)==8,"native epoll descriptor/data widths");
_Static_assert(offsetof(struct epoll_event,events)==0,"native event field origin");
#if defined(__x86_64__)
_Static_assert(sizeof(struct epoll_event)==12 && offsetof(struct epoll_event,data)==4,"native packed x86 epoll event stride");
#else
_Static_assert(sizeof(struct epoll_event)==16 && offsetof(struct epoll_event,data)==8,"native ARM epoll event stride");
#endif
#endif
