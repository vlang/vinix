// SPDX-License-Identifier: GPL-2.0-or-later
// Independent task-context observations; this is not the production leaf.
@[translated]
@[has_globals]
module sleepspy

#include "contract.h"

@[typedef]
struct C.vkh_const_char_p {}

fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
@[noreturn]
fn C.abort()
@[noreturn]
fn C.exit(i32)

__global (
	// An explicit nonzero initializer retains the production export-init guard.
	// Every test configures the context before observing it.
	vsl_mode i32 = -1
	vsl_irq_disabled bool
	vsl_pins u32
	vsl_depth u32
	vsl_queries u32
	vsl_conditions u32
	vsl_sequence u32
	vsl_ordered bool
	vsl_condition i32
	vsl_schedules u32
	vsl_safe_cases u32
	vsl_false_cases u32
	vsl_true_cases u32
)

pub fn require(valid bool, code i32) {
	if !valid {
		C.printf(c'FAIL: conditional sleep condition %d\n', code)
		C.fflush(unsafe { nil })
		C.exit(1)
	}
}

pub fn configure(mode i32, condition i32, ordered bool) {
	vsl_mode = mode
	vsl_irq_disabled = mode == 1
	vsl_pins = if mode == 2 { u32(1) } else { u32(0) }
	vsl_depth = if mode == 3 { u32(1) } else if mode == 4 { u32(2) } else { u32(0) }
	vsl_queries = 0
	vsl_conditions = 0
	vsl_sequence = 0
	vsl_ordered = ordered
	vsl_condition = condition
	vsl_schedules = 0
}

@[export: 'vinix_linuxkpi_may_sleep']
pub fn may_sleep() bool {
	vsl_queries++
	if vsl_ordered {
		require(vsl_conditions == 1 && vsl_sequence == 1, 1)
		vsl_sequence++
	}
	return !vsl_irq_disabled && vsl_pins == 0 && vsl_depth == 0
}

@[export: 'vsl_condition_value']
pub fn condition_value() i32 {
	vsl_conditions++
	vsl_sequence++
	return vsl_condition
}

@[export: 'schedule']
pub fn schedule() { vsl_schedules++ }

pub fn verify(queries u32, conditions u32) {
	require(vsl_queries == queries && vsl_conditions == conditions && vsl_schedules == 0, 2)
	require(vsl_irq_disabled == (vsl_mode == 1), 3)
	require(vsl_pins == (if vsl_mode == 2 { u32(1) } else { u32(0) }), 4)
	require(vsl_depth == (if vsl_mode == 3 { u32(1) } else if vsl_mode == 4 { u32(2) } else { u32(0) }), 5)
	vsl_safe_cases++
	if queries == 0 { vsl_false_cases++ } else { vsl_true_cases++ }
}

pub fn finish() {
	require(vsl_safe_cases == 31 && vsl_false_cases == 13 && vsl_true_cases == 18, 9)
}

@[export: 'vinix_linuxkpi_bug'; noreturn]
pub fn bug(file C.vkh_const_char_p, line i32) {
	verify(1, 1)
	require(vsl_mode > 0 && vsl_sequence == 2, 6)
	C.printf(c'BUG: mode=%d queries=%u conditions=%u file=%s line=%d\n', vsl_mode, vsl_queries, vsl_conditions, file, line)
	C.fflush(unsafe { nil })
	C.abort()
}
