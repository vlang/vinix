/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native declarations for an independent pinned RSP interpreter fixture. */
#ifndef VINIX_N64_RSP_NATIVE_ABI_H
#define VINIX_N64_RSP_NATIVE_ABI_H
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <m64p_plugin.h>
#include <budget.h>
typedef const char n64_const_char;
extern RSP_INFO RSP_info;
extern unsigned char *IMEM, *DMEM;
extern unsigned int *CR[16];
#define n64_rsp_info RSP_info
#define n64_rsp_imem IMEM
#define n64_rsp_dmem DMEM
#define n64_rsp_cr CR
void run_task(void);
_Static_assert(sizeof(unsigned int) == 4, "RSP register word width");
#endif
