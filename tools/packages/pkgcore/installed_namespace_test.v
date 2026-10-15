// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import time

#include <sys/resource.h>
#include <sys/wait.h>
fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int
fn C.chown(&char, i32, i32) i32
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
struct NamespaceLimit { current u64 maximum u64 }
$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn namespace_fixture() !(string, State, Plan) {
	work := os.temp_dir() + '/vinix-installed-namespace-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	mut packages := []Installed{}
	for id in ['app', 'runtime', 'assets'] {
		base := work + '/store/generations/1/apps/' + id
		os.mkdir_all(base + '/bin')!
		os.write_file(base + '/bin/app', 'authenticated payload')!; os.chmod(base + '/bin/app', 0o755)!
		p := Package{ id: id, name: id, version: '1.0.0', architecture: 'aarch64',
			kind: if id == 'app' { 'native' } else if id == 'runtime' { 'runtime' } else { 'data' }, license: 'MIT', entrypoint: 'bin/app',
			dependencies: if id == 'app' { [Dependency{ id: 'runtime' }, Dependency{ id: 'assets' }] } else { []Dependency{} },
			files: [Payload{ path: 'bin/app', bytes: 21, sha256: sha256.hexhash('authenticated payload'), executable: true }] }
		packages << Installed{ package: p, repository: 'fixture', sequence: 1,
			public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a' }
	}
	os.mkdir_all(work + '/store/generations/1/share/applications')!
	os.write_file(work + '/store/generations/1/share/applications/vinix-app.desktop', desktop_entry(packages[0].package))!
	os.chmod(work + '/store/generations/1/share/applications/vinix-app.desktop', 0o644)!
	return work, State{ generation: 1, architecture: 'aarch64', requested: ['app'], packages: packages }, Plan{ packages: packages }
}

fn test_verify_and_repair_discovery_refuse_undeclared_installed_payloads() {
	work, state, plan := namespace_fixture()!; defer { os.rmdir_all(work) or {} }
	path := work + '/store/generations/1/apps/runtime/lib'
	os.mkdir(path)!; os.write_file(path + '/undeclared.so', 'untrusted runtime code')!
	mut refused := false
	verify_installed(work + '/store', state, no_progress) or { refused = true }
	repairs := transaction_repairs(work + '/store', state, plan, 'install')
	defer { close_transaction_repairs(repairs) }
	println('INSTALLED NAMESPACE extra-runtime refused=${refused} repair=${repairs == ["runtime"]}')
	assert refused && repairs == ['runtime']
}

fn namespace_damage(work string, id string, kind string) ! {
	base := work + '/store/generations/1/apps/' + id
	match kind {
		'file' { os.write_file(base + '/extra', 'untrusted')! }
		'directory' { os.mkdir(base + '/extra')! }
		'fifo' { assert C.mkfifo((base + '/extra').str, 0o600) == 0 }
		'mode' { os.chmod(base + '/bin', 0o700)! }
		'nested-alias' { os.rename(base + '/bin', work + '/saved')!; os.symlink(work + '/saved', base + '/bin')! }
		'package-alias' { os.rename(base, work + '/saved')!; os.symlink(work + '/saved', base)! }
		'hardlink' { assert C.link((base + '/bin/app').str, (work + '/outside').str) == 0 }
		'missing' { os.rename(base + '/bin/app', work + '/saved')! }
		else { panic(kind) }
	}
}

fn namespace_restore(work string, id string, kind string) ! {
	base := work + '/store/generations/1/apps/' + id
	match kind {
		'file', 'fifo' { os.rm(base + '/extra')! }
		'directory' { os.rmdir(base + '/extra')! }
		'mode' { os.chmod(base + '/bin', 0o755)! }
		'nested-alias' { os.rm(base + '/bin')!; os.rename(work + '/saved', base + '/bin')! }
		'package-alias' { os.rm(base)!; os.rename(work + '/saved', base)! }
		'hardlink' { os.rm(work + '/outside')! }
		'missing' { os.rename(work + '/saved', base + '/bin/app')! }
		else { panic(kind) }
	}
}

fn test_installed_namespace_faults_bind_exact_package_repairs_without_mutation() {
	mut count := 0
	for id in ['app', 'runtime', 'assets'] {
		for kind in ['file', 'directory', 'fifo', 'mode', 'nested-alias', 'package-alias', 'hardlink', 'missing'] {
			work, state, plan := namespace_fixture()!; defer { os.rmdir_all(work) or {} }
			namespace_damage(work, id, kind)!
			mut refused := false
			verify_installed(work + '/store', state, no_progress) or { refused = err.msg().contains('namespace verification failed') }
			repairs := transaction_repairs(work + '/store', state, plan, 'install')
			assert refused && repairs == [id], id + '/' + kind
			close_transaction_repairs(repairs)
			base := if kind == 'package-alias' { work + '/saved' } else { work + '/store/generations/1/apps/' + id }
			if kind == 'mode' { assert os.lstat(base + '/bin')!.mode & 0o7777 == 0o700 }
			if kind == 'hardlink' { assert os.read_file(work + '/outside')! == 'authenticated payload' }
			namespace_restore(work, id, kind)!
			verify_installed(work + '/store', state, no_progress)!
			healthy := transaction_repairs(work + '/store', state, plan, 'install')
			assert healthy.len == 0; close_transaction_repairs(healthy)
			count++
		}
	}
	assert count == 24
	println('INSTALLED NAMESPACE 24 app/runtime/data extra-entry, alias, mode, hard-link and missing-entry refusals bind exact repair IDs; restored trees pass without mutation PASS')
}

fn test_installed_namespace_checks_generation_parents_and_owner_against_the_state_administrator() {
	work, state, plan := namespace_fixture()!; defer { os.rmdir_all(work) or {} }
	for relative in ['generations/1', 'generations/1/apps'] {
		path := work + '/store/' + relative
		os.rename(path, work + '/saved')!; os.symlink(work + '/saved', path)!
		mut refused := false
		verify_installed(work + '/store', state, no_progress) or { refused = true }
		repairs := transaction_repairs(work + '/store', state, plan, 'install')
		assert refused && repairs == ['app', 'assets', 'runtime']; close_transaction_repairs(repairs)
		os.rm(path)!; os.rename(work + '/saved', path)!
		verify_installed(work + '/store', state, no_progress)!
	}
	if os.geteuid() == 0 {
		for path in [work + '/store/generations/1/apps/app', work + '/store/generations/1/apps/app/bin', work + '/store/generations/1/apps/app/bin/app'] {
			assert C.chown(path.str, 1001, 1001) == 0
			assert !installed_namespace_valid(work + '/store', 1, state.packages[0].package)
			assert C.chown(path.str, 0, 0) == 0
		}
	}
	println('INSTALLED NAMESPACE generation/apps parent aliases refuse all package checks; root guest also checks package/directory/file foreign ownership PASS')
}

fn test_ordinary_launch_checks_administrator_owned_closure_before_data_preparation_or_execution() {
	work, state, _ := namespace_fixture()!; defer { os.rmdir_all(work) or {} }
	// Prepare faults as administrator; an ordinary child only reads/refuses.
	os.mkdir(work + '/home')!
	for id in ['app', 'runtime', 'assets'] {
		namespace_damage(work, id, 'file')!
		child := C.fork(); assert child >= 0
		if child == 0 {
			if os.geteuid() == 0 { assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0 }
			assert os.geteuid() != 0 && C.getegid() != 0
			os.setenv('HOME', work + '/home', true)
			config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'fixture', public_key: state.packages[0].public_key }] }
			mut refused := false
			run_leased_mode(config, work + '/store', state, 'app', LaunchInput{}) or { refused = err.msg().contains('namespace verification failed') }
			assert refused && !os.exists(work + '/home/.local')
			C._exit(0)
		}
		mut status := 0
		assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
		namespace_restore(work, id, 'file')!
	}
	// Ordinary verification must accept the restored root-owned generation.
	child := C.fork(); assert child >= 0
	if child == 0 {
		if os.geteuid() == 0 { assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0 }
		verify_installed(work + '/store', state, no_progress)!
		C._exit(0)
	}
	mut status := 0
	assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
	println('INSTALLED NAMESPACE ordinary launch refuses undeclared app/runtime/dependency entries before private-data creation or execution; restored administrator-owned trees verify PASS')
}

fn test_installed_namespace_bounds_descriptors_for_deep_wide_and_repeated_checks() {
	work, state, _ := namespace_fixture()!; defer { os.rmdir_all(work) or {} }
	p := state.packages[0].package
	base := work + '/store/generations/1/apps/app'
	deep := 'nested/'.repeat(64) + 'payload'
	os.mkdir_all(os.dir(base + '/' + deep))!
	os.rename(base + '/bin/app', base + '/' + deep)!; os.rmdir(base + '/bin')!
	deep_package := Package{ ...p, files: [Payload{ ...p.files[0], path: deep }] }
	mut original := NamespaceLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0
	limited := NamespaceLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &limited }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { &original }) == 0 }
	verify_installed_namespace(work + '/store', 1, deep_package)!
	os.mkdir(base + '/bin')!; os.rename(base + '/' + deep, base + '/bin/app')!
	os.rmdir_all(base + '/nested')!
	mut files := p.files.clone()
	for i in 0 .. 1024 {
		path := i.str() + '-' + 'x'.repeat(64)
		os.write_file(base + '/' + path, 'x')!
		files << Payload{ path: path, bytes: 1, sha256: sha256.hexhash('x') }
	}
	wide := Package{ ...p, files: files }
	verify_installed_namespace(work + '/store', 1, wide)!
	for _ in 0 .. 128 {
		verify_installed_namespace(work + '/store', 1, state.packages[1].package)!
		namespace_damage(work, 'runtime', 'file')!
		assert !installed_namespace_valid(work + '/store', 1, state.packages[1].package)
		namespace_restore(work, 'runtime', 'file')!
	}
	println('INSTALLED NAMESPACE 64-level and 1024-file inventories plus 128 successful/refused checks retire descriptors below 32 PASS')
}

fn test_installed_namespace_releases_owned_checker_scratch() {
	$if track_heap ? {
		work, state, _ := namespace_fixture()!; defer { os.rmdir_all(work) or {} }
		directory := work + '/store'
		for damaged in [false, true] {
			if damaged { namespace_damage(work, 'app', 'file')! }
			C.vinix_heap_begin()
			for _ in 0 .. 128 { assert installed_namespace_valid(directory, 1, state.packages[0].package) != damaged }
			bytes := C.vinix_heap_end(); assert bytes == 0 && C.vinix_heap_count() == 0
		}
		println('INSTALLED NAMESPACE 128 healthy and 128 refused namespace checks retain zero checker allocations PASS')
	}
}
