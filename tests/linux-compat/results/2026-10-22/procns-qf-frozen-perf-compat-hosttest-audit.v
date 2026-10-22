// SPDX-License-Identifier: GPL-2.0-or-later
// Regenerate audited declarations from the maintained exports and ABI schema.
module hosttest

import os

pub fn audit_headers(directory string) ! {
	audit_headers_from_source(directory,
		env_default('LINUXKPI_SOURCE_DIR', os.join_path(upstream_default(), 'linux-6.6.157')))!
}

pub fn audit_headers_from_source(directory string, linux string) ! {
	mut schemas := ['spinlock.json', 'atomic-exchange.json']
	mut headers := ['spinlock_adapters.h', 'atomic_exchange.h']
	if os.is_file(os.join_path(upstream_here(), 'abi/overflow.json')) {
		schemas << 'overflow.json'
		headers << 'integer_policy.h'
	}
	for index, schema in schemas {
		generate_abi(os.join_path(upstream_here(), 'abi', schema), upstream_here(),
			os.join_path(directory, 'vinix', headers[index]))!
	}
	generate_sched_mm(os.join_path(linux, 'include/linux/sched/mm.h'),
		os.join_path(directory, 'linux/sched/mm.h'))!
}
