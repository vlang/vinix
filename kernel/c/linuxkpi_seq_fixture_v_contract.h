/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_SEQ_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_SEQ_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/seqlock.h>
#include <linux/delay.h>
#include <linux/errno.h>
void *vinix_linuxkpi_fixture_seq_worker(void *);
#endif
