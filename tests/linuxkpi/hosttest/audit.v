// SPDX-License-Identifier: GPL-2.0-or-later
// Regenerate audited declarations from the maintained exports and ABI schema.
module hosttest

import os

pub fn audit_headers(directory string) ! {
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
}
