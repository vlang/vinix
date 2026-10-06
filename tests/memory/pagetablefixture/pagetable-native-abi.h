/* Native libc and volatile storage declarations; the regression is V. */
#ifndef VINIX_PAGETABLE_NATIVE_ABI_H
#define VINIX_PAGETABLE_NATIVE_ABI_H
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <sys/wait.h>
#include <unistd.h>
#if defined(__x86_64__)
#include <cpuid.h>
#endif
#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif
struct vqpt_byte { volatile unsigned char value; };
struct vqpt_signal { volatile sig_atomic_t value; };
_Static_assert(sizeof(sig_atomic_t) == 4, "original signal flag width");
_Static_assert(sizeof(struct vqpt_byte) == 1, "original volatile byte access");
_Static_assert(sizeof(uintptr_t) == 8 && sizeof(unsigned long) == 8, "native address/free-page words");
void vqpt_fault_handler(int);
#endif
