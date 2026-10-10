// SPDX-License-Identifier: GPL-2.0-or-later
module nativepolicy

import policyhost

const cpu_declarations = $embed_file('../cpufixture/declarations.v').to_string()
const cpu_assertions = $embed_file('../cpufixture/assertions.v').to_string()

fn cpu() ! {
	source := read(root() + '/kernel/proc/cpu_account.v')!
	mut program := cpu_declarations
	for name in ['expire_cpu_timer', 'cpu_signals_locked', 'cpu_timer_value'] {
		begin := source.index('fn ' + name + '(') or { return error('Missing function ' + name) }
		brace := begin + (source[begin..].index('{') or { return error('Missing function brace') })
		mut depth := 1
		mut end := brace + 1
		for depth > 0 && end < source.len {
			if source[end] == `{` { depth++ }
			if source[end] == `}` { depth-- }
			end++
		}
		if depth != 0 { return error('Unterminated production function ' + name) }
		program += source[begin..end] + '\n'
	}
	program += cpu_assertions
	work := private_work('vinix-cpu-logic-')!
	defer { retire(work) }
	write(work + '/cpu.v', program)!
	// Use the native host preference for both compilation and the fixture run.
	policyhost.run_fixture(work, false)!
}
