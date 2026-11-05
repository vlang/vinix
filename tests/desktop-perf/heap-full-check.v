// SPDX-License-Identifier: GPL-2.0-or-later
// Captured-log gate only; process exits and input audit receipts stay separate.
module main

import crypto.sha256
import heapfull
import json2
import os

// The unchanged report parser declares strtod through C.
#include <stdlib.h>

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selfcheck' {
		controls := heapfull.selfcheck()!
		println('PERF FULL HEAP explicit controls PASS ' + controls.str())
		return
	}
	if os.args.len != 3 || os.args[1] != 'check' {
		return error('usage: heap-full-check selfcheck | check SERIAL_LOG')
	}
	path := os.real_path(os.args[2])
	if path == '' || !os.is_file(path) || os.file_size(path) > heapfull.max_transcript_bytes {
		return error('regular serial log of at most 32 MiB required')
	}
	bytes := os.read_bytes(path)!
	report := heapfull.inspect(bytes)!
	println(json2.encode({
		'status': 'PASS full exact heap observations'
		'serial_path': path
		'serial_sha256': sha256.sum(bytes).hex()
		'cohorts': report.cohorts.str()
		'snapshots': report.snapshots.str()
		'delta_rows': report.delta_rows.str()
		'ops_rows': report.ops.str()
		'slab_rows': report.slab_rows.str()
		'physical_and_cache_observations': report.observations.join('\n')
		'scope': 'Fixed six-scenario completeness; 40 complete raw snapshot pairs, consistent full deltas, zero exact class objects/backing pages and large pages, and both after-free counters zero. Physical/cache interpretation, process exits and input audit receipts remain separate.'
	}))
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
