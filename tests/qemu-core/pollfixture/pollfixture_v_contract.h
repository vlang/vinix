/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef VINIX_QEMU_CORE_POLL_FIXTURE_NATIVE_ABI_H
#define VINIX_QEMU_CORE_POLL_FIXTURE_NATIVE_ABI_H
#include <errno.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
_Static_assert(sizeof(struct pollfd)==8,"native pollfd width");
_Static_assert(offsetof(struct pollfd,fd)==0 && offsetof(struct pollfd,events)==4 && offsetof(struct pollfd,revents)==6,"native pollfd field offsets");
_Static_assert(sizeof(int)==4 && sizeof(short)==2,"native descriptor/event widths");
_Static_assert(sizeof(nfds_t)==4 || sizeof(nfds_t)==8,"native poll count width");
#endif
