/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_PCI_CONFIG_FIXTURE_NATIVE_ABI_H
#define VINIX_PCI_CONFIG_FIXTURE_NATIVE_ABI_H
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <sched.h>
#include "pci_config.h"
/* Native storage only: V's Vinix backend cannot declare per-thread globals.
 * These are the original bool/unsigned words and original true/zero initializers.
 * No transport or oracle implementation lives in this header. */
static __thread bool pci_interrupts = true, pci_locked, pci_saved_interrupts;
static __thread unsigned int pci_pins, pci_saved_pins;
#define pci_mutex_initializer ((pthread_mutex_t)PTHREAD_MUTEX_INITIALIZER)
_Static_assert(sizeof(bool) == 1, "original TLS bool width");
_Static_assert(sizeof(unsigned int) == 4, "original unsigned counter width");
_Static_assert(sizeof(uint32_t) == 4 && sizeof(uint64_t) == 8, "PCI scalar widths");
_Static_assert(sizeof(size_t) == sizeof(uintptr_t), "original allocation scalar width");
_Static_assert(sizeof(pthread_t) == sizeof(uintptr_t), "native thread handle width");
#endif
