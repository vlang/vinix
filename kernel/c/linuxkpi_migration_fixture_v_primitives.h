/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_MIGRATION_FIXTURE_V_PRIMITIVES_H
#define VINIX_LINUXKPI_MIGRATION_FIXTURE_V_PRIMITIVES_H
#include <stdint.h>
struct vinix_migration_completion { uintptr_t words[4]; };
void vinix_linuxkpi_migration_fixture_disable(void);
void vinix_linuxkpi_migration_fixture_enable(void);
int64_t vinix_linuxkpi_migration_fixture_sleep(int64_t);
void vinix_linuxkpi_migration_fixture_init_completion(void *);
void vinix_linuxkpi_migration_fixture_complete(void *);
void vinix_linuxkpi_migration_fixture_wait(void *);
#endif
