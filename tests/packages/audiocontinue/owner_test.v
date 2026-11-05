// SPDX-License-Identifier: GPL-2.0-or-later
// These controls execute only the small synthetic fixture, never V, an audit,
// real captured inputs, target preparation or QEMU.
module audiocontinue

import json2
import os
import time
import nativeguard

#include <signal.h>
fn C.raise(i32) i32

fn owner_cleanup2(path string) {
	if os.getenv('AUDIO_CONTINUATION_RETAIN_FIXTURES') != '1' { os.rmdir_all(path) or {} }
}

fn owner_root2() !string {
	parent := os.getenv('AUDIO_CONTINUATION_TEST_ROOT')
	ordinary2(parent, 'directory')!
	root := parent + '/owner2-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	os.mkdir(root, mode: 0o700)!
	return root
}

fn owner_engine2(root string, mode string) !Engine2 {
	fixture := os.getenv('AUDIO_CONTINUATION_FIXTURE')
	ordinary2(fixture, 'file')!
	roots := os.getenv('AUDIO_CONTINUATION_CHARGED_ROOTS').split('|')
	if roots.len != 6 || !roots.any(under2(it, root)) { return error('owner controls require the same six charged roots') }
	usage2(roots)!
	for path in ['inputs/source', 'tmp', 'modules', 'fixture-compiler'] { os.mkdir_all(root + '/' + path)! }
	copy_new2(fixture, root + '/fixture-compiler/v', Donor2{})!
	os.chmod(root + '/fixture-compiler/v', 0o755)!
	write_new2(root + '/inputs/source/fixture-behavior', mode + '\n')!
	return Engine2{plan: Plan2{state_root: root, wall_ms: if mode == 'timeout' { 900 } else { 30000 },
		receipt_reserve_bytes: u64(16) << 20},
		legacy: LegacyPlan2{charged_roots: roots, roots: {'compiler': root + '/fixture-compiler'},
			files: {'clang': fixture, 'backend': fixture}},
		donor: Donor2{roots: {'capture': root + '/synthetic-capture'}, roles: expected_roles2()},
		plan_path: root + '/synthetic-plan.json', plan_sha256: '1'.repeat(64), started: time.sys_mono_now()}
}

fn test_engine_owner_controls_clean_nonzero_timeout_heldpipe_and_environment_restoration() {
	base := owner_root2() or { panic(err) }
	defer { owner_cleanup2(base) }
	saved := os.getenv_opt('CFLAGS')
	os.setenv('CFLAGS', 'parent-owner-sentinel', true)
	defer {
		if value := saved { os.setenv('CFLAGS', value, true) } else { os.unsetenv('CFLAGS') }
		nativeguard.watch_interrupts() or { panic(err) }
	}
	for mode in ['clean', 'nonzero', 'timeout', 'held-pipe'] {
		root := base + '/' + mode
		os.mkdir(root) or { panic(err) }
		mut engine := owner_engine2(root, mode) or { panic(err) }
		nativeguard.watch_interrupts() or { panic(err) }
		mut refused := false
		engine.command('cross-adapter-build.log') or { refused = true }
		assert refused == (mode != 'clean')
		assert os.getenv('CFLAGS') == 'parent-owner-sentinel'
		text := os.read_file(root + '/cross-adapter-build.log.result.json') or { panic(err) }
		result := json2.decode[nativeguard.Result](text) or { panic(err) }
		assert result.group_observed
		assert result.cleanup.reaped
		assert result.cleanup.group_empty
		assert result.cleanup.final_wait == -1
		assert result.cleanup.final_errno == C.ECHILD
		if mode == 'clean' { assert result.cleanup.exit_code == 0 && result.reason == '' }
		if mode == 'nonzero' { assert result.cleanup.exit_code == 7 }
		if mode == 'timeout' { assert result.reason.contains('deadline') }
		if mode == 'held-pipe' { assert result.held_pipe_after_leader_exit }
	}
}

fn test_sticky_owner_cancellation_refuses_publication_during_synchronous_gates() {
	root := owner_root2() or { panic(err) }
	defer { owner_cleanup2(root) }
	write_new2(root + '/preparation2.pending.json', 'never complete after cancellation\n') or { panic(err) }
	nativeguard.watch_interrupts() or { panic(err) }
	defer { nativeguard.watch_interrupts() or { panic(err) } }
	assert C.raise(i32(C.SIGTERM)) == 0
	gate := EngineCompletion2{engine: Engine2{plan: Plan2{state_root: root}}}
	mut refused := false
	gate.verify_cancellation() or { refused = true }
	assert refused
	assert !os.exists(root + '/preparation2.json')
}
