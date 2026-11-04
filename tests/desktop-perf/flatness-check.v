// SPDX-License-Identifier: GPL-2.0-or-later
// Captured-transcript gate only. Does not launch a VM or certify process exits.
module main

import crypto.sha256
import json2
import os
import perfflatness

// The shared report parser calls strtod through its C declaration.
#include <stdlib.h>

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selfcheck' {
		perfflatness.selfcheck()!
		return
	}
	if os.args.len != 3 || os.args[1] != 'check' {
		return error('usage: flatness-check selfcheck | check SERIAL_LOG')
	}
	path := os.real_path(os.args[2])
	if path == '' || !os.is_file(path) || os.file_size(path) > 32 * 1024 * 1024 {
		return error('regular serial log of at most 32 MiB required')
	}
	bytes := os.read_bytes(path)!
	report := perfflatness.inspect(bytes)!
	println(json2.encode({
		'status': 'PASS exact emitted slab deltas'
		'serial_path': path
		'serial_sha256': sha256.sum(bytes).hex()
		'ops_rows': report.ops.str()
		'slab_rows': report.slab_rows.str()
		'physical_and_cache_observations': report.observations.join('\n')
		'scope': 'Fixed six-scenario completeness and zero emitted slab deltas. Physical/cache interpretation, full class observation, actual process exits and input audits remain separate.'
	}))
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
