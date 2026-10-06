/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_PROCESSOR_H
#define VINIX_ASM_PROCESSOR_H
#include <vinix/runtime.h>

/* Original x86 processor.h supplies these page-table representations to
 * mm_types.h. Keep the configured upstream types; native Linux page ownership
 * and page-table operations require their own runtime implementations. */
#include <linux/init.h>
#include <asm/pgtable_types.h>

/* A native spin hint also services TLB shootdowns while IRQs are disabled.
 * Other Linux CPU and task-switch services are not supplied here. */
void cpu_relax(void);

/* Preserve the original x86 instruction helpers and their real dependencies.
 * Privileged writers and alternative patching keep their upstream externs;
 * CPU capability, mapping and device transport remain separate contracts. */
#ifndef VINIX_LINUXKPI_HOST_TEST
#include <linux/errno.h>
#include <asm/cpufeatures.h>
#include <asm/alternative.h>
#include <asm/special_insns.h>
#endif
#endif
