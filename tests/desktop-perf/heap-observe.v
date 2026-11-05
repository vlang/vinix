// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only host diagnostics. Complete arithmetic never implies qualification.
module main

import crypto.sha256
import heapfull
import json2
import os

#include <stdlib.h>

struct CapturedObservations {
	format int = 1
	qualification bool
	status string = 'NONQUALIFYING_OBSERVATIONS'
	serial_path string
	serial_sha256 string
	integer_encoding string = 'Counter values and deltas are exact decimal strings.'
	scope string = '44 measurements and DONE; 40 raw pairs, 80 snapshots and 640 canonical delta rows. Nonzero allocations, pages and corruption counters are recorded, never accepted as flatness. Process exits and immutable input/audit receipts remain separate.'
	observations heapfull.Observations
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == 'selfcheck' {
		controls := heapfull.observation_selfcheck()!
		strict := heapfull.selfcheck()!
		println('PERF HEAP OBSERVATION CONTROLS COMPLETE qualification=false controls=' + controls.str()
			+ ' unchanged_strict_controls=' + strict.str())
		return
	}
	if os.args.len != 3 || os.args[1] != 'check' {
		return error('usage: heap-observe selfcheck | check RETIRED_SERIAL_LOG')
	}
	path := os.real_path(os.args[2])
	if path == '' { return error('requires an existing serial log') }
	before := os.lstat(path)!
	if before.mode & 0o170000 != 0o100000 || before.size > heapfull.max_transcript_bytes {
		return error('requires a regular serial log of at most 32 MiB')
	}
	bytes := os.read_bytes(path)!
	after := os.lstat(path)!
	if before.dev != after.dev || before.inode != after.inode || before.mode != after.mode
		|| before.size != after.size || before.mtime != after.mtime || before.ctime != after.ctime
		|| u64(bytes.len) != after.size { return error('serial log changed during read') }
	report := heapfull.observe(bytes)!
	println(json2.encode(CapturedObservations{qualification: false, serial_path: path, serial_sha256: sha256.sum(bytes).hex(),
		observations: report}, prettify: true))
}

fn main() {
	run() or { eprintln('heap-observe: qualification=false: ' + err.msg()); exit(1) }
}
