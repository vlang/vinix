// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import time

#include <sys/resource.h>
#include <sys/wait.h>
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct LauncherLimit { current u64 maximum u64 }
$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.vinix_heap_size_at(u32) u64

fn registration_parent_fixture() !(string, State, Plan) {
	work := os.temp_dir() + '/vinix-launcher-parent-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := work + '/store/generations/1'
	os.mkdir_all(root + '/share/applications')!
	os.mkdir_all(root + '/apps/app/bin')!
	os.write_file(root + '/apps/app/bin/app', 'payload')!; os.chmod(root + '/apps/app/bin/app', 0o755)!
	p := Package{ id: 'app', name: 'App', version: '1.0.0', architecture: 'aarch64', kind: 'native',
		license: 'MIT', entrypoint: 'bin/app', associations: ['text/plain'],
		files: [Payload{ path: 'bin/app', bytes: 7, executable: true, sha256: sha256.hexhash('payload') }] }
	os.write_file(root + '/share/applications/vinix-app.desktop', desktop_entry(p))!
	os.chmod(root + '/share/applications/vinix-app.desktop', 0o644)!
	installed := Installed{ package: p, repository: 'trusted', public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', sequence: 1 }
	state := State{ generation: 1, architecture: 'aarch64', requested: ['app'], packages: [installed] }
	return work, state, Plan{ requested: state.requested, packages: state.packages }
}

fn test_launcher_parent_aliases_refuse_identical_canonical_entries() {
	for part in ['share', 'share/applications'] {
		work, state, plan := registration_parent_fixture()!; defer { os.rmdir_all(work) or {} }
		generation := work + '/store/generations/1'
		path := generation + '/' + part
		os.rename(path, work + '/outside')!; os.symlink(work + '/outside', path)!
		accepted := verified_registration(generation, state.packages[0].package)
		assert !accepted, part
		mut refused := false; verify_installed(work + '/store', state, no_progress) or { refused = true; unsafe { err.free() } }
		assert refused
		finding := inspect_installed_package(work + '/store', 1, state.packages[0].package)
		assert finding.issue == 'registration'; unsafe { finding.diagnostic.free() }
		repairs := transaction_repairs(work + '/store', state, plan, 'repair')
		assert repairs == ['app']; close_transaction_repairs(repairs)
		os.rm(path)!; os.rename(work + '/outside', path)!
		assert verified_registration(generation, state.packages[0].package)
	}
	println('LAUNCHER PARENTS identical external launchers through share/application aliases refuse Verify, classify health and bind repairs; restored parents pass PASS')
}

fn test_launcher_parent_modes_special_entries_and_legacy_hard_links() {
	work, state, _ := registration_parent_fixture()!; defer { os.rmdir_all(work) or {} }
	generation := work + '/store/generations/1'; p := state.packages[0].package
	entry := generation + '/share/applications/vinix-app.desktop'
	for part in ['', '/share', '/share/applications'] {
		path := generation + part
		for mode in [0o700, 0o777, 0o2755] {
			os.chmod(path, mode)!
			captured := os.lstat(path)!.mode & 0o7777
			assert verified_registration(generation, p) == (captured == 0o755)
			assert os.lstat(path)!.mode & 0o7777 == captured
		}
		os.chmod(path, 0o755)!
	}
	for part in ['share', 'share/applications'] {
		path := generation + '/' + part
		os.rename(path, work + '/saved')!
		for kind in ['file', 'fifo', 'missing'] {
			if kind == 'file' { os.write_file(path, 'not a directory')! }
			if kind == 'fifo' { assert C.mkfifo(path.str, 0o755) == 0 }
			assert !verified_registration(generation, p)
			if kind != 'missing' { os.rm(path)! }
		}
		os.rename(work + '/saved', path)!
	}
	assert C.link(entry.str, (work + '/hard-linked-launcher').str) == 0
	assert verified_registration(generation, p), 'canonical hard-linked launcher remains readable'
	os.rm(work + '/hard-linked-launcher')!
	assert verified_registration(generation, Package{ kind: 'runtime' }) && verified_registration(generation, Package{ kind: 'data' })
	// Before flush, a private stage can still have umask-restricted subdirectories.
	for part in ['', '/share', '/share/applications'] { os.chmod(generation + part, 0o700)! }
	assert verified_registration_with(generation, p, RegistrationOptions{ flushed: false })
	assert !verified_registration(generation, p)
	println('LAUNCHER PARENTS directory modes and special entries refuse without mutation; private staged admission and canonical hard-linked launchers remain supported PASS')
}

fn launcher_parent_mutate(phase string, _ string) ! {
	if phase != os.getenv('VINIX_LAUNCHER_PHASE') { return }
	path := os.getenv('VINIX_LAUNCHER_PATH')
	if os.getenv('VINIX_LAUNCHER_CHANGE') == 'mode' { os.chmod(path, 0o700)!; return }
	os.rename(path, path + '.saved')!
	os.symlink(path + '.saved', path)!
}

fn test_launcher_captured_parent_and_file_identities_rechecked_after_reads() {
	for phase in ['captured', 'opened', 'read'] {
		for part in ['', '/share', '/share/applications', '/share/applications/vinix-app.desktop'] {
			work, state, _ := registration_parent_fixture()!; defer { os.rmdir_all(work) or {} }
			generation := work + '/store/generations/1'; path := generation + part
			for kind in ['alias', 'mode'] {
				os.setenv('VINIX_LAUNCHER_PHASE', phase, true); os.setenv('VINIX_LAUNCHER_PATH', path, true); os.setenv('VINIX_LAUNCHER_CHANGE', kind, true)
				assert !verified_registration_with(generation, state.packages[0].package, RegistrationOptions{ checkpoint: launcher_parent_mutate }), phase + part + kind
				if kind == 'alias' { os.rm(path)!; os.rename(path + '.saved', path)! }
				else { os.chmod(path, if part.ends_with('.desktop') { 0o644 } else { 0o755 })! }
			}
		}
	}
	for key in ['VINIX_LAUNCHER_PHASE', 'VINIX_LAUNCHER_PATH', 'VINIX_LAUNCHER_CHANGE'] { os.unsetenv(key) }
	println('LAUNCHER PARENTS 24 captured/opened/read root, parent and leaf identity/mode mutations refuse PASS')
}

fn test_launcher_ordinary_account_rejects_damaged_registration_before_private_data_or_execution() {
	work, state, _ := registration_parent_fixture()!; defer { os.rmdir_all(work) or {} }
	generation := work + '/store/generations/1'
	os.mkdir(work + '/home')!
	for part in ['share', 'share/applications'] {
		path := generation + '/' + part
		os.rename(path, work + '/outside')!; os.symlink(work + '/outside', path)!
		child := C.fork(); assert child >= 0
		if child == 0 {
			if os.geteuid() == 0 { assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0 }
			assert os.geteuid() != 0 && C.getegid() != 0
			os.setenv('HOME', work + '/home', true)
			config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'trusted', public_key: state.packages[0].public_key }] }
			mut refused := false
			run_leased_mode(config, work + '/store', state, 'app', LaunchInput{}) or {
				message := err.msg(); refused = message.contains('registration verification failed'); unsafe { message.free(); err.free() }
			}
			assert refused && !os.exists(work + '/home/.local')
			C._exit(0)
		}
		mut status := 0; assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
		os.rm(path)!; os.rename(work + '/outside', path)!
	}
	if os.geteuid() == 0 {
		for part in ['/share', '/share/applications', '/share/applications/vinix-app.desktop'] {
			path := generation + part; assert C.chown(path.str, 1001, 1001) == 0
			assert !verified_registration(generation, state.packages[0].package)
			assert C.chown(path.str, 0, 0) == 0
		}
	}
	child := C.fork(); assert child >= 0
	if child == 0 {
		if os.geteuid() == 0 { assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0 }
		verify_installed(work + '/store', state, no_progress)!; C._exit(0)
	}
	mut status := 0; assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
	println('LAUNCHER PARENTS ordinary launch refuses damaged registration before private data or execution; restored administrator-owned launchers verify; guest root checks foreign ownership PASS')
}

fn test_launcher_parent_checks_retire_descriptors_and_owned_scratch() {
	work, state, _ := registration_parent_fixture()!; defer { os.rmdir_all(work) or {} }
	generation := work + '/store/generations/1'; path := generation + '/share'
	mut original := LauncherLimit{}; assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limited := LauncherLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limited }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	for damaged in [false, true]! {
		if damaged { os.rename(path, work + '/outside')!; os.symlink(work + '/outside', path)! }
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 128 { assert verified_registration(generation, state.packages[0].package) != damaged }
		$if track_heap ? {
			kept := C.vinix_heap_end()
			if kept != 0 { for index in 0 .. 12 { println('LAUNCHER ALLOCATION ' + C.vinix_heap_size_at(u32(index)).str()) } }
			assert kept == 0, 'launcher checks retained ${kept} bytes'
		}
	}
	println('LAUNCHER PARENTS 128 healthy and 128 refused checks pass below 32 descriptors; tracked host retains zero checker bytes PASS')
}
