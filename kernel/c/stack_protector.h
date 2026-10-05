// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
#ifndef VINIX_STACK_PROTECTOR_H
#define VINIX_STACK_PROTECTOR_H

#include <stdint.h>

__attribute__((noreturn)) void __stack_chk_fail(void);

// V implementations in lib/stack_protector.v and lib/stack_entropy_*.v.
// Attribute-bearing prototypes apply to generated definitions too: neither
// initialization body nor its C ABI wrapper may check the guard it replaces.
__attribute__((no_stack_protector)) void vinix_stack_guard_init(void);
__attribute__((no_stack_protector)) void lib__stack_guard_init(void);
__attribute__((no_stack_protector)) uint64_t lib__stack_boot_entropy(void);
__attribute__((no_stack_protector)) uint64_t lib__stack_mix64(uint64_t value);

#endif
