// SPDX-License-Identifier: GPL-2.0-or-later
// Compiler controls select genuine V-generated calls, never authored C bodies.
@[translated]
module aggregatecontrols

#include "contract.h"

@[typedef]
struct C.vag_control_type {}

@[c: 'arch_xchg_relaxed']
fn C.vag_control_exchange(&C.vag_control_type, C.vag_control_type) C.vag_control_type

@[c: 'arch_cmpxchg_relaxed']
fn C.vag_control_compare(&C.vag_control_type, C.vag_control_type, C.vag_control_type) C.vag_control_type

@[export: 'vag_probe_exchange']
pub fn exchange(pointer &C.vag_control_type, operand C.vag_control_type) {
	C.vag_control_exchange(pointer, operand)
}

@[export: 'vag_probe_compare']
pub fn compare(pointer &C.vag_control_type, expected C.vag_control_type, operand C.vag_control_type) {
	C.vag_control_compare(pointer, expected, operand)
}
