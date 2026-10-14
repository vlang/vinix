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
		else { return error('unknown coordination probe') }
	}
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
