/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_HOSTSEQ_V_CONTRACT_H
#define VINIX_LINUXKPI_HOSTSEQ_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <linux/seqlock.h>
void *vmh_fixture_seq_thread(void *);
#endif
