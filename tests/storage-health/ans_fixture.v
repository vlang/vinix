// SPDX-License-Identifier: GPL-2.0-or-later
// Install the maintained V hardware model into an isolated kernel worktree.
module main

import os

fn check_log(path string) ! {
	log := os.read_file(path)!
	if !log.contains('ANS HEALTH MODEL PASSED: 200 queries, no retained slab/large allocations') {
		return error('Missing ANS kernel model qualification')
	}
	if !log.contains('ANS STATUS MODEL PASSED: 200 read/write/flush/error cycles, no retained slab/large allocations') {
		return error('Missing ANS kernel status qualification')
	}
	mut classes := 0
	mut status_classes := 0
	for line in log.split_into_lines() {
		if line.starts_with('ANS HEALTH RETAIN size=') {
			if !line.ends_with(' delta=0') { return error('ANS heap retention: ${line}') }
			classes++
		}
		if line.starts_with('ANS STATUS RETAIN size=') {
			if !line.ends_with(' delta=0') { return error('ANS status heap retention: ${line}') }
			status_classes++
		}
	}
	if classes < 1 || status_classes != classes || log.contains('KERNEL PANIC') || log.contains('FATAL EXCEPTION') {
		return error('Incomplete or failed kernel model run')
	}
	println('PASS: 200 ARM kernel ANS health queries and read/write/flush/error cycles; ${classes} slab classes and large allocations stay flat')
}

fn prepare() ! {
	if os.args.len != 2 { return error('Usage: ans_fixture.v ISOLATED_WORKTREE') }
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.real_path(os.args[1])
	if work == os.real_path(root) { return error('Use an isolated git worktree') }
	path := work + '/kernel/apple/ans/ans.v'
	original := os.read_file(path)!
	committed := os.exec(['git', '-C', work, 'show', 'HEAD:kernel/apple/ans/ans.v'])
	production := os.read_file(root + '/kernel/apple/ans/ans.v')!
	if committed.exit_code != 0 || (committed.output != original && production != original) {
		return error('ANS boot source must match HEAD or the current production source')
	}
	needle := 'pub fn initialise(cmdline string) {'
	if original.count(needle) != 1 { return error('Missing ANS boot boundary') }
	mut model := os.read_file(root + '/tests/storage-health/ans_model.v')!
	model = model.all_before("@[export: 'vinix_account_disk_transfer']")
	model = model.replace('import klock', '').replace('fn C.posix_memalign(&voidptr, usize, usize) int', '')
	model = model.replace('mut pointer := unsafe { nil }\n\thealth_model_require(C.posix_memalign(&pointer, 16384, 4587520) == 0)',
		'pointer := C.calloc(1, 4587520)\n\thealth_model_require(pointer != unsafe { nil })')
	model = model.replace('\tassert klock.depth == 0\n', '').replace('\t\tassert klock.depth == 1\n', '')
	model = model.replace('\tassert klock.depth == 1\n', '')
	os.write_file(work + '/kernel/apple/ans/anscore/health_model_d_ans_health_fixture.v', model)!
	os.cp(root + '/tests/storage-health/ans_kernel_test.v',
		work + '/kernel/apple/ans/health_test_d_ans_health_fixture.v')!
	os.write_file(path, original.replace(needle, needle +
		'\n\t$if ans_health_fixture ? { health_fixture_run() }'))!
	println('Installed the ANS health model; build ARM with VFLAGS="-nocache -d ans_health_fixture"')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--log' {
		check_log(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
	} else {
		prepare() or {
			eprintln(err)
			exit(1)
		}
	}
}
