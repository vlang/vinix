/* SPDX-License-Identifier: MIT */
#ifndef VINIX_N64_BUDGET_H
#define VINIX_N64_BUDGET_H
#include <stdint.h>
extern uint64_t vinix_n64_cpu_budget;
extern uint64_t vinix_n64_rsp_budget;
void vinix_n64_budget_exhausted(void);
#endif
