/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_SMC_FIXTURE_ABI_H
#define VINIX_SMC_FIXTURE_ABI_H
#include "apple_smc.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int smc_fixture_tx(void *, uint64_t, uint8_t);
int smc_fixture_rx(void *, uint64_t *, uint8_t *);
uint64_t smc_fixture_tick(void *);
void smc_fixture_relax(void *);
#endif
