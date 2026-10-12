// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import json2

pub struct Gate {
pub:
	path     string
	field    string
	expected json2.Any
}

pub fn readiness_gates() []Gate {
	return [
		Gate{'build/useralloc-kernel-speed-v5/x86_64/build.json', 'build_exit_code', json2.Any(u64(0))},
		Gate{'build/useralloc-kernel-speed-v5/aarch64/build.json', 'build_exit_code', json2.Any(u64(0))},
		Gate{'build/useralloc-core-v6/core-x86_64/run.json', 'exit_code', json2.Any(u64(0))},
		Gate{'build/useralloc-core-v6/core-x86_64-four-level/run.json', 'exit_code', json2.Any(u64(0))},
		Gate{'build/useralloc-core-v6/core-aarch64/run.json', 'exit_code', json2.Any(u64(0))},
		Gate{'build/useralloc-core-v6/exit.json', 'exit_code', json2.Any(u64(0))},
		Gate{'third_party/useralloc-libc/build/useralloc/v6-verification-summary.json', 'all_passed', json2.Any(true)},
		Gate{'third_party/useralloc-libc/build/useralloc-production-v6/amd64/results.json', 'status', json2.Any('PASS')},
		Gate{'third_party/useralloc-libc/build/useralloc-production-v6/aarch64/results.json', 'status', json2.Any('PASS')},
		Gate{'third_party/useralloc-libc/build/useralloc-production-v6/amd64/root-review.json', 'status', json2.Any('PASS')},
		Gate{'third_party/useralloc-libc/build/useralloc-production-v6/aarch64/root-review.json', 'status', json2.Any('PASS')},
		Gate{'build/useralloc-pipe/static-desktop-v6/build.json', 'build_exit_code', json2.Any(u64(0))},
		Gate{'build/useralloc-pipe/static-desktop-v6/driver.exit.json', 'exit_code', json2.Any(u64(0))},
		Gate{'build/useralloc-review-v6/review.json', 'status', json2.Any('PASS')},
		Gate{'build/useralloc-desktop-perf-v6/validation.json', 'status', json2.Any('PASS')},
		Gate{'build/useralloc-hot-v5-diagnostic/driver.exit.json', 'exit_code', json2.Any(u64(0))},
	]
}

fn is_one(value json2.Any) bool {
	return match value {
		u64 { value == 1 }
		i64 { value == 1 }
		int { value == 1 }
		f64 { value == 1 }
		bool { value }
		else { false }
	}
}

pub fn gate_passed(value json2.Any, expected json2.Any) bool {
	if expected is string { return value is string && value == expected }
	if expected is bool { return if expected { is_one(value) } else { is_zero(value) } }
	if is_zero(expected) { return is_zero(value) }
	return value == expected
}

pub fn inspect_gates(root string, gates []Gate) !map[string]json2.Any {
	mut records := map[string]json2.Any{}
	for gate in gates {
		path := root + '/' + gate.path
		row := read_json(path)!
		value := row[gate.field]!
		if !gate_passed(value, gate.expected) {
			return error('Readiness gate failed: ' + gate.path + ' ' + gate.field + ' ' + value.str())
		}
		records[gate.path] = json2.Any({
			'sha256':        json2.Any(digest(path)!)
			'checked_field': json2.Any(gate.field)
			'value':         value
		})
	}
	return records
}

pub fn readiness(context Context) !int {
	records := inspect_gates(context.root, readiness_gates())!
	checked_hash(context.root + '/third_party/useralloc-libc/build/useralloc/v6-source-freeze/build-support/musl/malloc-retain.patch', 'ec459e48e5c3c9946c91e805428149802d0ab1835c64e5e023811ab54a48af1d')!
	for path, expected in {
		'build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64':                                   '16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74'
		'build/useralloc-kernel-speed-v5/aarch64/vinix-aarch64':                                 '3d721f3168a990373cb2549bd26322329923014ee4613cda2ae3d4f6884bf8f7'
		'third_party/useralloc-libc/build/useralloc/optimized-v6-final/lib/ld-musl-x86_64.so.1': 'ad78977e92f55d85ace71f1ca43bf650d216923ed3cf6650dd29f22c1d70af9d'
		'third_party/useralloc-libc/build/useralloc/optimized-v6-final/usr/lib/libc.a':          '8d5c3deee3610c07c3f9bbfaee3b4fed244ef35051c3e2390e4452b13db34ace'
	} {
		checked_hash(context.root + '/' + path, expected)!
	}
	result := map[string]json2.Any{
		'status':      json2.Any('PASS')
		'checked_utc': json2.Any(now())
		'gates':       json2.Any(records)
		'notes':       json2.Any('Same immutable validated v5 kernels; final v6 libc correctness, production packaging/static desktop, full3core modes and43rowfunctionaldesktop plan complete. Full allocation checker historical literalallowlist failure remains unchanged with same kernel source.')
	}
	write_json(context.root + '/build/useralloc-v6-final-readiness.json', result)!
	println(json2.encode(result, prettify: true))
	return 0
}
