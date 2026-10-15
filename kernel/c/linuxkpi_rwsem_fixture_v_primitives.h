/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RWSEM_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_RWSEM_FIXTURE_V_PRIMITIVES_H
#include <stdint.h>
#include <stdbool.h>
/* Opaque storage only; the typed facade checks the original records. */
struct vinix_rwsem_fixture { uintptr_t words[5]; };
struct vinix_rwsem_completion { uintptr_t words[4]; };
void *vinix_linuxkpi_rwsem_fixture_static(void);
void vinix_linuxkpi_rwsem_fixture_init(void *);
int32_t vinix_linuxkpi_rwsem_fixture_read(void *, uint32_t);
int32_t vinix_linuxkpi_rwsem_fixture_write(void *, bool);
int32_t vinix_linuxkpi_rwsem_fixture_try(void *, bool);
void vinix_linuxkpi_rwsem_fixture_up(void *, uint32_t);
void vinix_linuxkpi_rwsem_fixture_downgrade(void *);
int64_t vinix_linuxkpi_rwsem_fixture_value(void *, uint32_t);
void vinix_linuxkpi_rwsem_fixture_init_completion(void *);
void vinix_linuxkpi_rwsem_fixture_complete(void *);
void vinix_linuxkpi_rwsem_fixture_wait(void *);
void *vinix_linuxkpi_rwsem_fixture_alloc(void);
void vinix_linuxkpi_rwsem_fixture_free(void *);
#endif
