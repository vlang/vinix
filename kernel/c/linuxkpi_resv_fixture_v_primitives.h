/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RESV_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_RESV_FIXTURE_V_PRIMITIVES_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
/* Original records, used only as complete and correctly aligned storage. */
struct vinix_resv_fixture { uintptr_t lock[5]; void *fences; };
struct vinix_resv_iter_fixture {
    void *obj;
    uint32_t usage;
    void *fence;
    uint32_t fence_usage, index;
    void *fences;
    uint32_t num_fences;
    bool is_restarted;
};
uint32_t vinix_linuxkpi_resv_fixture_bytes(uint32_t);
void vinix_linuxkpi_resv_fixture_init(void *);
void vinix_linuxkpi_resv_fixture_fini(void *);
int32_t vinix_linuxkpi_resv_fixture_lock(void *, uint32_t);
void vinix_linuxkpi_resv_fixture_unlock(void *);
bool vinix_linuxkpi_resv_fixture_locked(void *);
int32_t vinix_linuxkpi_resv_fixture_reserve(void *, uint32_t);
void vinix_linuxkpi_resv_fixture_add(void *, void *, uint32_t);
void vinix_linuxkpi_resv_fixture_replace(void *, uint64_t, void *, uint32_t);
int32_t vinix_linuxkpi_resv_fixture_copy(void *, void *);
void vinix_linuxkpi_resv_fixture_begin(void *, void *, uint32_t);
void *vinix_linuxkpi_resv_fixture_step(void *, uint32_t);
void vinix_linuxkpi_resv_fixture_end(void *);
uint32_t vinix_linuxkpi_resv_fixture_cursor(void *, uint32_t);
void *vinix_linuxkpi_resv_fixture_list(void *);
uint64_t vinix_linuxkpi_resv_fixture_list_value(void *, uint32_t, uint32_t);
int32_t vinix_linuxkpi_resv_fixture_get(void *, uint32_t, uint32_t *, void **);
int32_t vinix_linuxkpi_resv_fixture_singleton(void *, uint32_t, void **);
int64_t vinix_linuxkpi_resv_fixture_wait(void *, uint32_t, bool, uint64_t);
void vinix_linuxkpi_resv_fixture_deadline(void *, uint32_t, int64_t);
bool vinix_linuxkpi_resv_fixture_signaled(void *, uint32_t);
size_t vinix_linuxkpi_resv_fixture_roundup(size_t);
void *vinix_linuxkpi_resv_fixture_realloc(void *, size_t, size_t);
#endif
