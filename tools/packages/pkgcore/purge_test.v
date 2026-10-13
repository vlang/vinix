// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import net.unix
import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.mkfifo(&char, u32) int
struct PurgeLimit { current u64 maximum u64 }

fn purge_work() !string {
	path := os.real_path(os.temp_dir()) + '/vpurge-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(path)!
	return path
}

fn test_personal_purge_removes_data_without_following_nested_links_or_opening_special_files() {
	work := purge_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	data := home + '/.local/share/vinix-apps/app'
	os.mkdir_all(data + '/nested')!
	os.mkdir_all(work + '/outside')!
	os.write_file(work + '/outside/kept', 'outside')!
	os.write_file(data + '/nested/with spaces; $literal', 'data')!
	os.symlink(work + '/outside', data + '/directory-link')!
	os.symlink(work + '/outside/kept', data + '/file-link')!
	os.symlink('absent', data + '/dangling-link')!
	assert C.mkfifo((data + '/fifo').str, 0o600) == 0
	mut socket := unix.listen_stream(data + '/socket', unix.ListenOptions{})!
	defer { socket.close() or {} }
	// Wide trees and long generation histories must retire each descriptor.
	for index in 0 .. 96 { os.mkdir_all(data + '/child-' + index.str() + '/inner')! }
	mut original := PurgeLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := PurgeLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	assert purge_personal_data(home, 'app', u32(os.geteuid()))!
	assert !os.exists(data) && os.read_file(work + '/outside/kept')! == 'outside'
	assert !purge_personal_data(home, 'app', u32(os.geteuid()))!
}

fn test_purge_refuses_parent_and_top_level_aliases_wrong_owner_and_shared_parents() {
	for part in ['.local', '.local/share', '.local/share/vinix-apps', '.local/share/vinix-apps/app'] {
		work := purge_work()!
		defer { os.rmdir_all(work) or { panic(err) } }
		home := work + '/home'
		os.mkdir_all(os.dir(home + '/' + part))!
		os.mkdir_all(work + '/outside')!
		os.write_file(work + '/outside/kept', 'outside')!
		os.symlink(work + '/outside', home + '/' + part)!
		mut refused := false
		purge_personal_data(home, 'app', u32(os.geteuid())) or { refused = err.msg().contains('ordinary directory') }
		assert refused && os.read_file(work + '/outside/kept')! == 'outside'
		assert os.is_link(home + '/' + part)
	}
	work := purge_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	data := home + '/.local/share/vinix-apps/app'
	os.mkdir_all(data)!
	os.write_file(data + '/kept', 'data')!
	for wrong_uid in [u32(os.geteuid()) + 1] {
		mut refused := false
		purge_personal_data(home, 'app', wrong_uid) or { refused = true }
		assert refused && os.exists(data + '/kept')
	}
	os.chmod(home + '/.local/share', 0o777)!
	mut shared_refused := false
	purge_personal_data(home, 'app', u32(os.geteuid())) or { shared_refused = true }
	assert shared_refused && os.exists(data + '/kept')
	os.chmod(home + '/.local/share', 0o755)!
	for invalid in ['../outside', '', '/outside'] {
		mut refused := false
		purge_personal_data(home, invalid, u32(os.geteuid())) or { refused = true }
		assert refused && os.exists(data + '/kept')
	}
}

fn test_purge_checks_128_generation_leases_with_32_fds_and_rejects_installed_or_corrupt_state() {
	work := purge_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	os.mkdir_all(work + '/generations')!
	os.write_file(work + '/lock', '')!
	app := Package{ id: 'app', name: 'App', version: '1.0.0', architecture: 'aarch64', license: 'MIT', kind: 'native', entrypoint: 'bin/app',
		files: [Payload{ path: 'bin/app', bytes: 1, sha256: 'a'.repeat(64), executable: true }] }
	installed := Installed{ package: app, repository: 'fixture', public_key: 'b'.repeat(64), sequence: 1 }
	for generation in 1 .. 130 {
		path := work + '/generations/' + generation.str()
		os.mkdir(path)!
		os.write_file(path + '/lease', '')!
		state := State{ generation: u64(generation), previous: 0, architecture: 'aarch64',
			requested: if generation < 129 { ['app'] } else { []string{} }, packages: if generation < 129 { [installed] } else { []Installed{} } }
		os.write_file(path + '/state.json', json2.encode(state))!
	}
	os.symlink('generations/1', work + '/current')!
	mut installed_refused := false
	check_purge_generations(work, 'aarch64', 'app') or { installed_refused = err.msg().contains('remove the application') }
	assert installed_refused
	os.rm(work + '/current')!; os.symlink('generations/129', work + '/current')!
	guard := acquire_reader(work)!
	defer { guard.release() }
	writer := C.open((work + '/lock').str, C.O_RDWR | C.O_CLOEXEC)
	assert writer >= 0 && C.flock(writer, C.LOCK_EX | C.LOCK_NB) != 0
	C.close(writer)
	lease := C.open((work + '/generations/64/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	assert lease >= 0 && C.flock(lease, C.LOCK_SH) == 0
	defer { C.close(lease) }
	mut original := PurgeLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := PurgeLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	mut busy := false
	check_purge_generations(work, 'aarch64', 'app') or { busy = err.msg().contains('still in use') }
	assert busy
	assert C.flock(lease, C.LOCK_UN) == 0
	check_purge_generations(work, 'aarch64', 'app')!
	original_state := os.read_file(work + '/generations/5/state.json')!
	os.write_file(work + '/generations/5/state.json', '{}')!
	mut corrupt := false
	check_purge_generations(work, 'aarch64', 'app') or { corrupt = true }
	assert corrupt
	os.write_file(work + '/generations/5/state.json', original_state)!
	os.rm(work + '/generations/5/lease')!
	assert C.mkfifo((work + '/generations/5/lease').str, 0o600) == 0
	mut special := false
	check_purge_generations(work, 'aarch64', 'app') or { special = err.msg().contains('regular file') }
	assert special
}

fn assert_purge_special_refusal(home string, data string, kind string) ! {
	mut refused := false
	purge_personal_data(home, 'app', u32(os.geteuid())) or { refused = err.msg().contains('ordinary directory') }
	assert refused && os.exists(data), kind
}

fn test_purge_refuses_top_level_special_files_and_excessive_depth() {
	for kind in ['fifo', 'socket', 'regular'] {
		work := purge_work()!
		defer { os.rmdir_all(work) or { panic(err) } }
		home := work + '/home'
		data := home + '/.local/share/vinix-apps/app'
		os.mkdir_all(os.dir(data))!
		match kind {
			'fifo' { assert C.mkfifo(data.str, 0o600) == 0; assert_purge_special_refusal(home, data, kind)! }
			'socket' {
				mut socket := unix.listen_stream(data, unix.ListenOptions{})!
				defer { socket.close() or {} }
				assert_purge_special_refusal(home, data, kind)!
			}
			else { os.write_file(data, 'keep')!; assert_purge_special_refusal(home, data, kind)! }
		}
	}
	work := purge_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	data := home + '/.local/share/vinix-apps/app'
	deep := data + '/d'.repeat(65)
	os.mkdir_all(deep)!
	mut refused := false
	purge_personal_data(home, 'app', u32(os.geteuid())) or { refused = err.msg().contains('depth limit') }
	assert refused && os.exists(deep)
}

fn test_purge_identity_check_refuses_a_replaced_directory() {
	work := purge_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	os.mkdir(work + '/data')!
	parent := C.open(work.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	assert parent >= 0
	defer { C.close(parent) }
	mut original := C.stat{}
	assert C.fstatat(parent, c'data', &original, C.AT_SYMLINK_NOFOLLOW) == 0
	os.rename(work + '/data', work + '/saved')!
	os.mkdir(work + '/data')!
	os.write_file(work + '/data/kept', 'replacement')!
	mut refused := false
	purge_same_entry(parent, c'data', original) or { refused = err.msg().contains('changed during purge') }
	assert refused && os.read_file(work + '/data/kept')! == 'replacement'
}
