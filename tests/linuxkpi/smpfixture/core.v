// SPDX-License-Identifier: GPL-2.0-or-later
// Independent original Linux CSD compiler/runtime fixtures; no SMP implementation.
module smpfixture

import os
import hosttest

pub fn flags(linux string, include string, target string, standard string) []string {
	mut selected := ['--target=' + target, '-std=' + standard, '-O2', '-ffreestanding', '-fwrapv',
		'-nostdinc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-unused-function',
		'-D__KERNEL__', '-include', 'linux/kconfig.h', '-include',
		os.join_path(linux, 'include/linux/compiler_types.h'), '-isystem',
		os.join_path(hosttest.root(), 'kernel/freestnd-c-hdrs')]
	for path in [include, os.join_path(hosttest.upstream_here(), 'include'),
		os.join_path(hosttest.root(), 'kernel/c'), os.join_path(linux, 'include'),
		os.join_path(linux, 'include/uapi'), os.join_path(linux, 'arch/x86/include'),
		os.join_path(linux, 'arch/x86/include/uapi')] {
		selected << ['-I', path]
	}
	return selected
}

// Preserve the complete physical macro, including every continuation/newline.
pub fn macros(text string, name string) ![]string {
	mut found := []string{}
	lines := text.split_into_lines()
	mut offset := 0
	mut index := 0
	for index < lines.len {
		line := lines[index]
		start := offset
		offset += line.len + if offset + line.len < text.len { 1 } else { 0 }
		index++
		if !line.starts_with('#define') { continue }
		remaining := line[7..]
		if remaining.len == 0 || remaining[0] !in [` `, `\t`] { continue }
		if !remaining.trim_left(' \t').starts_with(name + '(') { continue }
		mut current := line
		for current.trim_right(' \t\r\n\v\f').ends_with('\\') {
			if index >= lines.len { return error('Incomplete pinned macro: ' + name) }
			current = lines[index]
			offset += current.len + if offset + current.len < text.len { 1 } else { 0 }
			index++
		}
		found << text[start..offset]
	}
	return found
}

pub fn macro(text string, name string) !string {
	all := macros(text, name)!
	if all.len == 0 { return error('Missing exact pinned declaration macro: ' + name) }
	return all[0]
}

pub const node = '
#include <linux/smp_types.h>
#include <linux/llist.h>
_Static_assert(sizeof(struct llist_node) == 8, "original intrusive link");
_Static_assert(sizeof(struct __call_single_node) == 16, "original CSD node");
_Static_assert(_Alignof(struct __call_single_node) == 8, "original node alignment");
_Static_assert(offsetof(struct __call_single_node, llist) == 0, "original link offset");
_Static_assert(offsetof(struct __call_single_node, u_flags) == 8, "original flags offset");
_Static_assert(offsetof(struct __call_single_node, a_flags) == 8, "original atomic union");
_Static_assert(offsetof(struct __call_single_node, src) == 12, "original source offset");
_Static_assert(offsetof(struct __call_single_node, dst) == 14, "original target offset");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_node *)0)->u_flags), unsigned int), "flag type");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_node *)0)->a_flags), atomic_t), "atomic flag type");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_node *)0)->llist.next), struct llist_node *), "link type");
_Static_assert(CSD_FLAG_LOCK == 1 && CSD_TYPE_ASYNC == 0 && CSD_TYPE_SYNC == 0x10 &&
    CSD_TYPE_IRQ_WORK == 0x20 && CSD_TYPE_TTWU == 0x30 && CSD_FLAG_TYPE_MASK == 0xf0,
    "original call-single flag values");
_Static_assert(IRQ_WORK_PENDING == 1 && IRQ_WORK_BUSY == 2 && IRQ_WORK_LAZY == 4 &&
    IRQ_WORK_HARD_IRQ == 8 && IRQ_WORK_CLAIMED == 3, "original IRQ-work flags");
unsigned long csd_node_bytes(void) { return sizeof(struct __call_single_node); }
'

pub const layout = '
_Static_assert(CONFIG_64BIT == 1, "64-bit record profile");
_Static_assert(sizeof(struct __call_single_data) == 32 && sizeof(call_single_data_t) == 32,
    "original CSD width");
_Static_assert(_Alignof(struct __call_single_data) == 8 && _Alignof(call_single_data_t) == 32,
    "original ordinary struct versus cacheline typedef alignment");
_Static_assert(offsetof(struct __call_single_data, node) == 0 &&
    offsetof(struct __call_single_data, func) == 16 &&
    offsetof(struct __call_single_data, info) == 24, "original data offsets");
_Static_assert(__builtin_types_compatible_p(smp_call_func_t, void (*)(void *)),
    "original callback ABI");
_Static_assert(__builtin_types_compatible_p(smp_cond_func_t, bool (*)(int, void *)),
    "original sender condition ABI");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_data *)0)->func), smp_call_func_t), "function field");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_data *)0)->info), void *), "borrowed argument field");
static void callback(void *info) { (void)info; }
static int sentinel;
static call_single_data_t file_initialized = CSD_INIT(callback, &sentinel);
unsigned long csd_record_bytes(void) { return sizeof(file_initialized); }
bool csd_file_initializer_valid(void) {
    return !file_initialized.node.llist.next && !file_initialized.node.u_flags &&
        !file_initialized.node.src && !file_initialized.node.dst &&
        file_initialized.func == callback && file_initialized.info == &sentinel;
}
unsigned long csd_array_stride(void) { call_single_data_t pair[2]; return
    (unsigned long)((char *)&pair[1] - (char *)&pair[0]); }
'

pub const runtime = '
extern void csd_model_check(bool passed, int line);
#define CHECK(x) csd_model_check((x), __LINE__)
static unsigned function_evaluations, info_evaluations, target_evaluations;
static void *expected_info;
static call_single_data_t target;
static smp_call_func_t select_function(void) { function_evaluations++; return callback; }
static void *select_info(void) { info_evaluations++; return expected_info; }
static call_single_data_t *select_target(void) { target_evaluations++; return &target; }
static void check_csd(const struct __call_single_data *csd) {
    CHECK(csd->node.llist.next == NULL); CHECK(csd->node.u_flags == 0);
    CHECK(csd->node.src == 0); CHECK(csd->node.dst == 0);
    CHECK(csd->func == callback); CHECK(csd->info == expected_info);
}
void csd_test_initializers(void *info, unsigned iterations) {
    expected_info = info;
    CHECK(csd_file_initializer_valid()); CHECK(csd_array_stride() == 32);
    for (unsigned i = 0; i < iterations; i++) {
        function_evaluations = info_evaluations = target_evaluations = 0;
        struct __call_single_data local = CSD_INIT(select_function(), select_info());
        CHECK(function_evaluations == 1 && info_evaluations == 1); check_csd(&local);
        target.node.llist.next = &target.node.llist; target.node.u_flags = ~0u;
        target.node.src = 0xffff; target.node.dst = 0xffff;
        target.func = NULL; target.info = NULL;
        INIT_CSD(select_target(), select_function(), select_info());
        CHECK(function_evaluations == 2 && info_evaluations == 2 && target_evaluations == 1);
        check_csd(&target);
        struct __call_single_data nulls = CSD_INIT(NULL, NULL);
        CHECK(!nulls.node.llist.next && !nulls.node.u_flags && !nulls.node.src &&
              !nulls.node.dst && !nulls.func && !nulls.info);
        INIT_CSD(&nulls, callback, info); check_csd(&nulls);
    }
}
'

pub const reference = '
int (*single_reference)(int, smp_call_func_t, void *, int) = smp_call_function_single;
int (*async_reference)(int, struct __call_single_data *) = smp_call_function_single_async;
void (*many_reference)(const struct cpumask *, smp_call_func_t, void *, bool) = smp_call_function_many;
void (*all_reference)(smp_call_func_t, void *, int) = smp_call_function;
void (*conditional_reference)(smp_cond_func_t, smp_call_func_t, void *, bool,
    const struct cpumask *) = on_each_cpu_cond_mask;
void (*queue_reference)(int, struct llist_node *) = __smp_call_single_queue;
void call_original_wrappers(smp_call_func_t function, smp_cond_func_t condition,
    void *info, const struct cpumask *mask) {
    on_each_cpu(function, info, 1); on_each_cpu_mask(mask, function, info, true);
    on_each_cpu_cond(condition, function, info, true);
}
void call_original_arch_ipi(int cpu, const struct cpumask *mask) {
    arch_send_call_function_single_ipi(cpu); arch_send_call_function_ipi_mask(mask);
}
'

pub const driver = '
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
void csd_test_initializers(void *, unsigned);
static unsigned assertions;
void csd_model_check(bool passed, int line) {
    assertions++; if (!passed) { fprintf(stderr, "Original CSD assertion line %d\\n",line); abort(); }
}
int main(void) {
    int argument = 42;
    csd_test_initializers(&argument, 10000); csd_test_initializers(NULL, 10000);
    printf("PASS: %u original CSD initializer assertions\\n",assertions); return 0;
}
'
