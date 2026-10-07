/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_HOSTTASKFLAG_V_CONTRACT_H
#define VINIX_LINUXKPI_HOSTTASKFLAG_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <linux/vtime.h>
_Static_assert(PF_VCPU == 0x00000001, "Linux 6.6 guest-task flag");
_Static_assert(PF_EXITING == 0x00000004, "Linux 6.6 terminal exit flag");
_Static_assert(sizeof(struct task_struct) <= 64, "native embedded task view");
void *vmh_task_flag_late_view_worker(void *);
void *vmh_task_flag_wake_worker(void *);
void vmh_task_flag_tests(void);
#endif
