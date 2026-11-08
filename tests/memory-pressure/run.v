// SPDX-License-Identifier: GPL-2.0-or-later
// V host runner for the production pressure policy and subscription resource.
module main

import os

fn put(root string, name string, text string) ! {
	os.mkdir_all(os.dir(root + '/' + name))!
	os.write_file(root + '/' + name, text + '\n')!
}
fn run() ! {
	if os.args.len != 2 || os.exists(os.args[1]) { return error('Usage: run.v FRESH-STATE') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	state := os.args[1]
	os.mkdir_all(state)!
	for pair in [['kernel/file/memory_pressure.v', 'file/memory_pressure.v'],
		['tests/memory-pressure/pressure_test.v', 'file/pressure_test.v'],
		['kernel/memory/pressure_policy.v', 'memory/pressure_policy.v'],
		['tests/memory-pressure/policy_test.v', 'memory/policy_test.v']] {
		put(state, 'modules/' + pair[1], os.read_file(root + '/' + pair[0])!)!
	}
	put(state, 'v.mod', "Module { name: 'memory_pressure_tests' }")!
	stubs := {
		'file/constants.v': 'module file\npub const pollin = 1',
		'klock/klock.v': 'module klock\nimport sync\npub struct Lock { mut: mutex sync.Mutex }\npub fn (mut l Lock) acquire() { l.mutex.lock() }\npub fn (mut l Lock) release() { l.mutex.unlock() }',
		'katomic/katomic.v': 'module katomic\npub fn inc[T](mut n T) T { old := n; n++; return old }\npub fn dec[T](mut n T) bool { old := n; n--; return old != 1 }',
		'stat/stat.v': 'module stat\npub struct Stat { pub mut: mode u32 }\npub fn isreg(mode u32) bool { return mode & 0xf000 == 0x8000 }\npub fn isdir(mode u32) bool { return mode & 0xf000 == 0x4000 }',
		'event/eventstruct/eventstruct.v': 'module eventstruct\npub struct Event { pub mut: generation u64 }',
		'event/event.v': 'module event\nimport event.eventstruct\npub fn trigger(mut e eventstruct.Event, drop bool) u64 { e.generation++; return 0 }',
		'errno/errno.v': '@[has_globals]\nmodule errno\npub const eacces = 13\npub const eperm = 1\npub const enospc = 28\n__global (last_error int)\npub fn set(value int) { last_error = value }\npub fn get() int { return last_error }',
		'memory/snapshot.v': '@[has_globals]\nmodule memory\npub struct PressureSnapshot { pub: level int generation u64 free_bytes u64 total_bytes u64 watermarks PressureWatermarks reclaim_runs u64 reclaimed_pages u64 allocation_failures u64 }\n__global ( test_pressure_snapshot PressureSnapshot test_pressure_observer fn (u64) = unsafe { nil } )\npub fn register_pressure_observer(callback fn (u64)) { test_pressure_observer = callback }\npub fn pressure_snapshot() PressureSnapshot { return test_pressure_snapshot }\npub fn set_snapshot(level int, generation u64) { test_pressure_snapshot = PressureSnapshot{level: level, generation: generation}; if test_pressure_observer != unsafe { nil } { test_pressure_observer(generation) } }',
	}
	for name, text in stubs { put(state, 'modules/' + name, text) ! }
	resource_source := os.read_file(root + '/kernel/resource/resource.v')!.all_before('__global (').replace('import ioctl\n', '')
	put(state, 'modules/resource/resource.v', resource_source + '\npub const o_directory = 0o200000\npub const o_nofollow = 0o400000\npub fn default_ioctl(handle voidptr, request u64, argp voidptr) ?int { return none }\nfn C.__builtin_alloca(uint) voidptr')!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or {
		os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	}
	mut p := os.new_process(compiler)
	p.set_args(['-cc', 'clang', '-enable-globals', '-gc', 'none', '-path', os.real_path(state + '/modules') + '|@vlib', 'test', state + '/modules/memory', state + '/modules/file'])
	p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	os.write_file(state + '/tests.log', output)!
	print(output)
	if code != 0 { return error('Memory pressure host tests failed') }
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
