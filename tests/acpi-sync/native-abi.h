/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ACPI_NATIVE_FIXTURE_ABI_H
#define VINIX_ACPI_NATIVE_FIXTURE_ABI_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <pthread.h>
#include <string.h>
typedef unsigned long long vacpi_ull;
_Static_assert(sizeof(vacpi_ull) == sizeof(uint64_t), "native snapshot varargs width");
void *vinix_acpi_sync_create(bool);
bool vinix_acpi_sync_destroy(void *);
int vinix_acpi_sync_wait(void *, uint16_t);
bool vinix_acpi_sync_signal(void *);
void vinix_acpi_sync_reset(void *);
void vinix_acpi_sync_sleep(uint64_t);
uint64_t vinix_acpi_sync_clock_ns(void);
uint64_t vinix_acpi_sync_thread_id(void);
void vinix_acpi_sync_heap_snapshot(uint64_t *);
int kprintf(const char *, ...);
#ifndef __AARCH64__
void serial__out(char);
#endif
void *vinix_acpi_fixture_mutex_worker(void *);
void *vinix_acpi_fixture_event_worker(void *);
void *vinix_acpi_fixture_wrong_owner(void *);
void *vinix_acpi_fixture_delayed_signal(void *);
#endif
