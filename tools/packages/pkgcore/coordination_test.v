// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import net.unix
import os
import time

#include <sys/wait.h>
#include <sys/resource.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.mkfifo(&char, u32) int
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.link(&char, &char) int

struct CoordinationLimit { current u64 maximum u64 }

fn coordination_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-coordination-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/etc/vinix-packages')!
	os.write_file(work + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: 'aarch64' }))!
	directory := state_directory(work)
	os.mkdir_all(directory + '/generations/1')!
	os.mkdir(directory + '/objects')!
	os.write_file(directory + '/lock', '')!
	os.write_file(directory + '/generations/1/lease', '')!
	app := Package{ id: 'app', name: 'App', version: '1.0.0', architecture: 'aarch64', kind: 'native',
		license: 'MIT', entrypoint: 'bin/app', files: [Payload{ path: 'bin/app', bytes: 1, sha256: 'a'.repeat(64), executable: true }] }
	os.write_file(directory + '/generations/1/state.json', json2.encode(State{ generation: 1, architecture: 'aarch64',
		requested: ['app'], packages: [Installed{ package: app, repository: 'fixture', public_key: 'b'.repeat(64), sequence: 1 }] }))!
	os.symlink('generations/1', directory + '/current')!
	return work
}

fn coordination_attempt(root string, operation string) ! {
	directory := state_directory(root)
	match operation {
		'reader' { guard := acquire_reader(directory)!; guard.release() }
		'writer' { guard := acquire(directory)!; guard.release() }
		'status' { (Service{ root: root }).state()! }
		'legacy-launch' { run_application(Config{ architecture: 'aarch64' }, directory, 'app', [])! }
		'lease' {
			state, lease := generation_lease(directory, 'aarch64', 'app')!
			C.close(lease); close_decoded_state(state)
		}
		'collection' { lease := open_collection_generation(directory + '/generations/1')!; close_collection_lease(lease) }
		'purge' { check_purge_generation(directory + '/generations/1', 'app', 1)! }
		else { return error('unknown coordination probe') }
	}
}

fn test_hardlinked_coordination_files_refuse_before_permission_changes_or_locking() {
	for entry in ['lock', 'generations/1/lease'] {
		work := coordination_fixture()!; defer { os.rmdir_all(work) or {} }
		directory := state_directory(work)
		path := directory + '/' + entry
		outside := work + '/outside'
		os.write_file(outside, 'preserved')!; os.chmod(outside, 0o600)!
		os.rm(path)!; assert C.link(outside.str, path.str) == 0
		operations := if entry == 'lock' { ['writer', 'reader', 'status'] } else { ['lease', 'collection', 'purge'] }
		for operation in operations {
			mut message := ''
			coordination_attempt(work, operation) or { message = err.msg() }
			preserved := os.read_file(outside)! == 'preserved' && os.lstat(outside)!.mode & 0o777 == 0o600
			println('COORDINATION IDENTITY ' + entry + '/' + operation + ' refused=' + message.contains('hard link').str() + ' preserved=' + preserved.str())
			assert message.contains('hard link') && preserved, message
			assert os.readlink(directory + '/current')! == 'generations/1' && os.exists(path)
		}
		// Retire only the deliberate alias, leaving external data untouched.
		os.rm(path)!; os.write_file(path, '')!; os.chmod(path, 0o644)!
		for operation in operations { coordination_attempt(work, operation)! }
	}
	println('COORDINATION IDENTITY state reader/writer/status and launch/collection/purge refuse hard links before mutation; restored entries retry PASS')
}

fn test_coordination_capture_refuses_replaced_names_and_preserves_held_inode() {
	work := coordination_fixture()!; defer { os.rmdir_all(work) or {} }
	path := state_directory(work) + '/lock'
	outside := work + '/outside'
	os.write_file(outside, 'preserved')!
	for kind in ['ordinary', 'symlink', 'fifo', 'directory', 'missing', 'unlinked'] {
		fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
		assert fd >= 0 && C.flock(fd, C.LOCK_SH | C.LOCK_NB) == 0
		check_coordination_file(fd, path, 'test package lock')!
		os.rename(path, path + '.saved')!
		if kind == 'ordinary' { os.write_file(path, 'replacement')! }
		else if kind == 'unlinked' { os.rm(path + '.saved')! }
		else { coordination_special(path, kind, outside)! }
		mut refused := false
		check_coordination_file(fd, path, 'test package lock') or {
			refused = err.msg().contains('changed during admission') || err.msg().contains('hard links')
		}
		assert refused && os.read_file(outside)! == 'preserved', kind
		if kind == 'ordinary' { assert os.read_file(path)! == 'replacement' }
		if os.exists(path) || os.is_link(path) {
			if kind == 'directory' { os.rmdir(path)! } else { os.rm(path)! }
		}
		if kind == 'unlinked' { os.write_file(path, '')! }
		else { os.rename(path + '.saved', path)!; check_coordination_file(fd, path, 'test package lock')! }
		C.close(fd)
		guard := acquire(state_directory(work))!; guard.release()
	}
	// Collection/purge rechecks resolve the lease relative to its captured parent.
	directory := state_directory(work) + '/generations/1'
	lease_path := directory + '/lease'
	lease := open_collection_generation(directory)!
	os.rename(lease_path, lease_path + '.saved')!; os.write_file(lease_path, '')!
	mut refused := false
	check_collection_lease(lease) or { refused = err.msg().contains('changed during admission') }
	assert refused && os.exists(lease_path + '.saved')
	os.rm(lease_path)!; os.rename(lease_path + '.saved', lease_path)!
	check_collection_lease(lease)!; close_collection_lease(lease)
	println('COORDINATION IDENTITY captured locks reject replaced/unlinked names and captured-parent lease changes without mutating replacements; restored identities retry PASS')
}

fn test_hardlinked_lease_collection_preflight_preserves_all_generations_and_cache() {
	work := coordination_fixture()!; defer { os.rmdir_all(work) or {} }
	directory := state_directory(work)
	current := read_state(directory, 'aarch64')!; defer { close_decoded_state(current) }
	for generation in [u64(2), 3] {
		path := directory + '/generations/' + generation.str()
		os.mkdir(path)!; os.write_file(path + '/lease', '')!
		os.write_file(path + '/state.json', json2.encode(State{ ...current, generation: generation }))!
	}
	object := directory + '/objects/' + 'd'.repeat(64)
	os.write_file(object, 'keep')!
	outside := work + '/outside'
	os.write_file(outside, 'preserved')!; os.chmod(outside, 0o600)!
	path := directory + '/generations/3/lease'
	os.rm(path)!; assert C.link(outside.str, path.str) == 0
	mut refused := false
	collect(Config{ architecture: 'aarch64' }, directory) or { refused = err.msg().contains('hard link') }
	assert refused && os.ls(directory + '/generations')!.sorted() == ['1', '2', '3']
	assert os.read_file(object)! == 'keep' && os.read_file(outside)! == 'preserved'
	os.rm(path)!; os.write_file(path, '')!
	collect(Config{ architecture: 'aarch64' }, directory)!
	assert os.ls(directory + '/generations')! == ['1'] && !os.exists(object)
	assert os.read_file(outside)! == 'preserved' && os.lstat(outside)!.mode & 0o777 == 0o600
	println('COORDINATION IDENTITY malformed obsolete lease refuses collection before any generation/cache removal; restored lease permits collection PASS')
}

fn test_hardlinked_coordination_refusals_retire_descriptors_and_preserve_exclusion() {
	work := coordination_fixture()!; defer { os.rmdir_all(work) or {} }
	directory := state_directory(work)
	outside := work + '/outside'
	os.write_file(outside, 'preserved')!; os.chmod(outside, 0o600)!
	for entry in ['lock', 'generations/1/lease'] {
		os.rm(directory + '/' + entry)!
		assert C.link(outside.str, (directory + '/' + entry).str) == 0
	}
	mut original := CoordinationLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limit := CoordinationLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 {
		for operation in ['writer', 'reader', 'status', 'lease', 'collection', 'purge'] {
			mut refused := false
			coordination_attempt(work, operation) or {
				message := err.msg(); refused = message.contains('hard link')
				unsafe { message.free(); err.free() }
			}
			assert refused, operation
		}
	}
	for entry in ['lock', 'generations/1/lease'] { os.rm(directory + '/' + entry)!; os.write_file(directory + '/' + entry, '')! }
	reader := acquire_reader(directory)!
	// A busy writer must not chmod a reader's captured inode before refusal.
	os.chmod(directory + '/lock', 0o600)!
	mut refused := false
	acquire(directory) or { refused = err.msg().contains('another package transaction') }
	assert refused && os.lstat(directory + '/lock')!.mode & 0o777 == 0o600
	reader.release()
	writer := acquire(directory)!; assert os.lstat(directory + '/lock')!.mode & 0o777 == 0o644; writer.release()
	for operation in ['reader', 'writer', 'status', 'lease', 'collection', 'purge'] { coordination_attempt(work, operation)! }
	assert os.read_file(outside)! == 'preserved' && os.lstat(outside)!.mode & 0o777 == 0o600
	println('COORDINATION IDENTITY 128 repeats of six hard-link refusals retire descriptors under a 32-descriptor limit; busy writer preserves permissions and restored exclusion PASS')
}

// A broken blocking open/flock must fail this assertion instead of hanging the
// test driver. The child cannot outlive two seconds even on unchanged sources.
fn coordination_refusal(root string, operation string, kind string) {
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.alarm(2)
		coordination_attempt(root, operation) or {
			message := err.msg()
			if message.contains('lock') || message.contains('lease') || message.contains('state is unavailable')
				|| message.contains('another package transaction') {
				C._exit(0)
			}
			eprintln(message)
			C._exit(43)
		}
		C._exit(42) // unsafe entry was admitted
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child
	assert status == 0, '${operation}/${kind}: expected prompt refusal, wait status ${status}'
}

fn coordination_special(path string, kind string, outside string) ! {
	match kind {
		'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
		'directory' { os.mkdir(path)! }
		'symlink' { os.symlink(outside, path)! }
		'dangling' { os.symlink(outside + '-absent', path)! }
		'missing' {}
		else { return error('unknown special entry') }
	}
}

fn test_package_locks_refuse_special_files_without_waiting_or_changing_them() {
	for kind in ['fifo', 'directory', 'symlink', 'dangling', 'missing', 'socket'] {
		work := coordination_fixture()!
		defer { os.rmdir_all(work) or { panic(err) } }
		path := state_directory(work) + '/lock'
		outside := work + '/outside'
		os.write_file(outside, 'preserved')!
		os.chmod(outside, 0o600)!
		os.rm(path)!
		mut socket := &unix.StreamListener(unsafe { nil })
		if kind == 'socket' { socket = unix.listen_stream(path, unix.ListenOptions{})! }
		else { coordination_special(path, kind, outside)! }
		defer { if kind == 'socket' { socket.close() or {} } }
		for operation in ['reader', 'status'] { coordination_refusal(work, operation, kind) }
		// No --root support exists for legacy launches. The direct API is used
		// only by an ordinary account; root's path delegates to its session tool.
		if os.geteuid() != 0 { coordination_refusal(work, 'legacy-launch', kind) }
		if kind != 'missing' { coordination_refusal(work, 'writer', kind) }
		assert os.read_file(outside)! == 'preserved' && os.lstat(outside)!.mode & 0o777 == 0o600
		if kind == 'fifo' { assert os.lstat(path)!.mode & 0o777 == 0o600 }
		if kind == 'missing' { assert !os.exists(path) }
	}
	println('Package coordination: malformed locks refuse promptly without changing special entries or link targets')
}

fn test_generation_leases_refuse_special_files_and_busy_exclusive_holders() {
	for kind in ['fifo', 'directory', 'symlink', 'dangling', 'missing', 'socket', 'exclusive'] {
		work := coordination_fixture()!
		defer { os.rmdir_all(work) or { panic(err) } }
		directory := state_directory(work)
		path := directory + '/generations/1/lease'
		outside := work + '/outside'
		os.write_file(outside, 'preserved')!
		mut held := -1
		mut socket := &unix.StreamListener(unsafe { nil })
		if kind == 'exclusive' {
			held = C.open(path.str, C.O_RDONLY | C.O_CLOEXEC)
			assert held >= 0 && C.flock(held, C.LOCK_EX | C.LOCK_NB) == 0
		} else {
			os.rm(path)!
			if kind == 'socket' { socket = unix.listen_stream(path, unix.ListenOptions{})! }
			else { coordination_special(path, kind, outside)! }
		}
		defer { if kind == 'socket' { socket.close() or {} }; if held >= 0 { C.close(held) } }
		coordination_refusal(work, 'lease', kind)
		assert os.readlink(directory + '/current')! == 'generations/1' && os.read_file(outside)! == 'preserved'
	}
	println('Package coordination: malformed and exclusively held generation leases refuse within the deadline')
}

fn test_legacy_and_service_readers_refuse_busy_writer_without_waiting() {
	work := coordination_fixture()!
	defer { os.rmdir_all(work) or { panic(err) } }
	guard := acquire(state_directory(work))!
	defer { guard.release() }
	for operation in ['reader', 'status'] { coordination_refusal(work, operation, 'busy-writer') }
	if os.geteuid() != 0 { coordination_refusal(work, 'legacy-launch', 'busy-writer') }
}

fn test_fresh_reads_remain_available_but_durable_metadata_requires_its_missing_lock() {
	work := coordination_fixture()!
	defer { os.rmdir_all(work) or { panic(err) } }
	directory := state_directory(work)
	os.rmdir_all(directory)!
	service := Service{ root: work }
	assert service.state()!.generation == 0
	assert service.policy()!.architecture == 'aarch64'
	assert repository_status(work)!.history.len == 0
	assert software_view(work, true)!.rows.len == 0
	assert !os.exists(directory)
	os.mkdir_all(directory)!
	for name in ['catalog.json', 'trust-history.json'] {
		path := directory + '/' + name
		// Refuse missing coordination before parsing even damaged metadata.
		os.write_file(path, '{broken')!
		mut state_refused := false
		mut policy_refused := false
		mut history_refused := false
		mut view_refused := false
		service.state() or { state_refused = err.msg().contains('state is unavailable') }
		service.policy() or { policy_refused = err.msg().contains('state is unavailable') }
		repository_status(work) or { history_refused = err.msg().contains('state is unavailable') }
		software_view(work, true) or { view_refused = err.msg().contains('state is unavailable') }
		assert state_refused && policy_refused && history_refused && view_refused
		assert os.read_file(path)! == '{broken' && !os.exists(directory + '/lock')
		os.rm(path)!
	}
	assert service.state()!.generation == 0
	println('Package coordination: fresh read-only status stays available; retained metadata without its lock refuses before parsing')
}

fn test_valid_locks_and_generation_leases_preserve_exclusion_and_release_descriptors() {
	work := coordination_fixture()!
	defer { os.rmdir_all(work) or { panic(err) } }
	directory := state_directory(work)
	mut original := CoordinationLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0
	limited := CoordinationLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&original)) == 0 }
	for _ in 0 .. 128 {
		reader := acquire_reader(directory)!
		mut refused := false
		acquire(directory) or { refused = err.msg().contains('another package transaction') }
		assert refused
		state, lease := generation_lease(directory, 'aarch64', 'app')!
		other := C.open((directory + '/generations/1/lease').str, C.O_RDONLY | C.O_CLOEXEC)
		assert other >= 0 && C.flock(other, C.LOCK_EX | C.LOCK_NB) != 0
		C.close(lease); close_decoded_state(state)
		assert C.flock(other, C.LOCK_EX | C.LOCK_NB) == 0
		C.close(other); reader.release()
		writer := acquire(directory)!
		refused = false
		acquire_reader(directory) or { refused = err.msg().contains('another package transaction') }
		assert refused
		writer.release()
	}
	// Repeated type failures must close descriptors too, including the decoded
	// state owned by a refused launch. Restoring each entry permits normal use.
	for name in ['lock', 'generations/1/lease'] {
		path := directory + '/' + name
		os.rm(path)!
		assert C.mkfifo(path.str, 0o600) == 0
		// A peer also bounds the repeated regression probes on old sources.
		peer := C.open(path.str, C.O_RDWR | C.O_NONBLOCK | C.O_CLOEXEC)
		assert peer >= 0
		for _ in 0 .. 128 {
			if name == 'lock' {
				mut read_refused := false
				mut write_refused := false
				acquire_reader(directory) or { read_refused = err.msg().contains('ordinary regular file') }
				acquire(directory) or { write_refused = err.msg().contains('ordinary regular file') }
				assert read_refused && write_refused
			} else {
				mut refused := false
				generation_lease(directory, 'aarch64', 'app') or { refused = err.msg().contains('ordinary regular file') }
				assert refused
			}
		}
		C.close(peer)
		os.rm(path)!
		os.write_file(path, '')!
	}
	coordination_attempt(work, 'reader')!
	coordination_attempt(work, 'writer')!
	coordination_attempt(work, 'lease')!
	println('Package coordination: 128 valid and repeated malformed reader/writer/lease cycles preserve exclusion and recovery under a 32-descriptor limit')
}
