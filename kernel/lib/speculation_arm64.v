// SPDX-License-Identifier: GPL-2.0-or-later
module lib

@[export: 'vinix_speculation_init']
fn speculation_init(cpu_number u64) u64 {
	_ = cpu_number
	return 0
}

@[export: 'vinix_speculation_switch']
fn speculation_switch(policy u64) {
	_ = policy
}
