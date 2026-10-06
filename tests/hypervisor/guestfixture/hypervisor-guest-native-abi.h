#ifndef VINIX_HYPERVISOR_GUEST_NATIVE_ABI_H
#define VINIX_HYPERVISOR_GUEST_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include "../../../base-files/usr/include/vinix/hypervisor.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#ifdef __APPLE__
#define __errno_location __error
#endif
_Static_assert(sizeof(struct vinix_hv_registers) == 15 * sizeof(uint64_t),
               "original public register ABI");
#endif
