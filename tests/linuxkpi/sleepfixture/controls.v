// SPDX-License-Identifier: GPL-2.0-or-later
// C rejects non-scalar predicates at the actual generated adapter call.
@[translated]
module sleepcontrols

#include "contract.h"

@[typedef]
struct C.vsl_control {}

@[c: 'might_sleep_if']
fn C.probe(C.vsl_control)

@[export: 'vsl_nonscalar_control']
pub fn probe(value C.vsl_control) { C.probe(value) }
