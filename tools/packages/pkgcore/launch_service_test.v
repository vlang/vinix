// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

#include <sys/wait.h>
#include <grp.h>
fn C.waitpid(int, &int, int) int
fn C.setgroups(usize, &u32) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.alarm(u32) u32
fn C.mkfifo(&char, u32) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn launch_service_architecture() string { return $if arm64 { 'aarch64' } $else { 'x86_64' } }
fn launch_service_cycles() int { return $if track_heap ? { 1000 } $else { 16 } }

fn launch_service_fixture(root string, architecture string, count int) !Service {
	os.mkdir_all(root + '/etc/vinix-packages')!
	key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	mut repositories := []Repository{cap: count}
	mut packages := []Installed{cap: count}
	mut requested := []string{cap: count}
	mut allowed := []string{cap: count}
	mut pins := []Dependency{cap: count}
	for i in 0 .. count {
		number := i.str(); defer { unsafe { number.free() } }
		id := if i == 0 { 'app'.clone() } else { 'app-' + number }
		repository := 'publisher-' + number
		requested << id.clone(); allowed << id.clone(); pins << Dependency{ id: id, minimum: '1.0.0', before: '2.0.0' }
		repositories << Repository{ id: repository, url: 'file:///offline/é🚀', public_key: key }
		packages << Installed{ repository: repository, public_key: key, sequence: 7,
			package: Package{ id: id, version: '1.0.0', architecture: architecture, name: 'Launch fixture', kind: 'native', license: 'MIT',
				permissions: ['files'], entrypoint: 'bin/app', files: [Payload{ path: 'bin/app', sha256: key, bytes: 1, executable: true }] } }
	}
	config := Config{ architecture: architecture, repositories: repositories, policy: Policy{ allowed: allowed, pins: pins, permissions: ['files'],
		licenses: ['Vendor é🚀'], allow_firmware: true, reserve_bytes: 17 } }
	text := json2.encode(config); defer { unsafe { text.free() } }
	os.write_file(root + '/etc/vinix-packages/config.json', text)!
	service := Service{ root: root, offline: true }
	directory := state_directory(root); defer { unsafe { directory.free() } }
	guard := acquire(directory)!; guard.release()
	os.mkdir_all(directory + '/generations/7')!
	state := State{ architecture: architecture, generation: 7, requested: requested, packages: packages }
	metadata := encode_generation_state(state)!; defer { unsafe { metadata.free() } }
	os.write_file(directory + '/generations/7/state.json', metadata)!
	os.write_file(directory + '/generations/7/lease', '')!
	os.symlink('generations/7', directory + '/current')!
	return service
}

fn launch_service_root(label string) string {
	return os.temp_dir() + '/vinix-launch-service-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
}

fn launch_service_failure(service Service, id string, expected string, cycles int) {
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. cycles {
		if mut prepared := service.prepare_launch(id) { prepared.close(); assert false }
		else { message := err.msg(); assert message.contains(expected), message; unsafe { message.free(); err.free() } }
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, expected + ' retained ' + kept.str() }
}

fn launch_service_ordinary_failure(service Service, id string, expected string) {
	if os.geteuid() != 0 { launch_service_failure(service, id, expected, launch_service_cycles()); return }
	child := C.fork(); assert child >= 0
	if child == 0 {
		C.alarm(60)
		assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
		launch_service_failure(service, id, expected, launch_service_cycles())
		C._exit(0)
	}
	mut status := 0; assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0, expected
}

fn launch_service_owned_snapshots() ! {
	for architecture in ['aarch64', 'x86_64']! {
		for count in [1, 64]! {
			root := launch_service_root('owned'); defer { os.rmdir_all(root) or {} }
			service := launch_service_fixture(root, architecture, count)!
			directory := state_directory(root); defer { unsafe { directory.free() } }
			cycles := if count == 1 { launch_service_cycles() } else { 16 }
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. cycles {
				mut prepared := service.prepare_launch('app')!
				assert prepared.directory == directory && prepared.config.architecture == architecture && prepared.config.policy.offline
				assert prepared.config.repositories.len == count && prepared.config.policy.pins.len == count
				assert prepared.state.generation == if os.geteuid() == 0 { u64(0) } else { u64(7) }
				prepared.close(); prepared.close()
				assert prepared.lease == -1 && prepared.directory == '' && prepared.state.generation == 0
				assert prepared.config.architecture == '' && prepared.config.policy.permissions.len == 0
			}
			$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, 'prepare retained ' + kept.str() }
			mut first := service.prepare_launch('app')!; mut second := service.prepare_launch('app')!
			assert first.config.architecture.str != second.config.architecture.str
			if first.lease >= 0 {
				lease := first.lease
				assert lease != second.lease && first.state.packages.data != second.state.packages.data
				probe := C.open((directory + '/generations/7/lease').str, C.O_RDONLY | C.O_CLOEXEC)
				assert probe >= 0 && C.flock(probe, C.LOCK_EX | C.LOCK_NB) != 0
				first.close()
				spare := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC); assert spare >= 0
				assert C.dup2(spare, lease) == lease
				first.close(); assert C.fcntl(lease, C.F_GETFD) >= 0
				assert C.flock(probe, C.LOCK_EX | C.LOCK_NB) != 0
				second.close(); assert C.flock(probe, C.LOCK_EX | C.LOCK_NB) == 0
				C.close(probe); C.close(lease); if spare != lease { C.close(spare) }
				second = service.prepare_launch('app')!
			} else { first.close() }
			// Preparation no longer holds the reader while a runner owns the snapshot.
			guard := acquire(directory)!; guard.release()
			os.write_file(root + '/etc/vinix-packages/config.json', '{retired configuration')!
			if second.lease >= 0 { assert second.state.packages.len == count }
			assert second.config.repositories[0].url == 'file:///offline/é🚀' && second.config.policy.licenses[0] == 'Vendor é🚀'
			second.close(); second.close()
		}
	}
	$if track_heap ? { println('LAUNCH SERVICE tracked preparation: 1000 small and 16 large cycles per architecture retained 0 bytes') }
}

fn test_prepared_launch_owns_snapshots_and_releases_only_its_lease() {
	if os.geteuid() == 0 {
		child := C.fork(); assert child >= 0
		if child == 0 {
			C.alarm(120)
			assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
			launch_service_owned_snapshots()!
			C._exit(0)
		}
		mut status := 0; assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
	} else { launch_service_owned_snapshots()! }
	println('LAUNCH SERVICE both architectures, independent 1/64-entry snapshots, offline overlay, reusable close, reader release and exact generation lease lifetime PASS')
}

fn test_session_executable_lookup_owns_and_retires_its_path() {
	expected := os.executable(); defer { unsafe { expected.free() } }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. launch_service_cycles() {
		first := session_executable()!
		second := session_executable()!
		assert first == expected && first.str != second.str
		unsafe { first.free() }
		assert second == expected
		unsafe { second.free() }
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	println('LAUNCH SERVICE executable identity owns independent paths and retires lookup scratch PASS')
}

fn test_prepare_launch_refusals_retire_partial_configuration_and_descriptors() {
	root := launch_service_root('refusal'); defer { os.rmdir_all(root) or {} }
	service := launch_service_fixture(root, 'aarch64', 1)!
	directory := state_directory(root); configuration := root + '/etc/vinix-packages/config.json'
	metadata := directory + '/generations/7/state.json'; lease := directory + '/generations/7/lease'
	original_config := os.read_file(configuration)!; original_state := os.read_file(metadata)!
	launch_service_failure(Service{ root: 'relative' }, 'app', 'absolute directory', launch_service_cycles())
	guard := acquire(directory)!
	os.write_file(configuration, '{invalid configuration')!
	launch_service_failure(service, 'app', 'another package transaction', launch_service_cycles())
	guard.release()
	launch_service_failure(service, 'app', 'invalid package configuration:', launch_service_cycles())
	os.write_file(configuration, original_config)!
	launch_service_ordinary_failure(service, 'missing', 'application is not installed: missing')
	os.write_file(metadata, '{invalid state')!
	launch_service_ordinary_failure(service, 'app', 'invalid package metadata JSON structure')
	os.write_file(metadata, original_state)!
	os.rm(lease)!
	launch_service_ordinary_failure(service, 'app', 'cannot open application generation lease')
	assert C.mkfifo(lease.str, 0o644) == 0
	launch_service_ordinary_failure(service, 'app', 'ordinary regular file')
	os.rm(lease)!; os.write_file(lease, '')!
	os.link(lease, lease + '.link')!
	launch_service_ordinary_failure(service, 'app', 'without hard links')
	os.rm(lease + '.link')!
	fd := C.open(lease.str, C.O_RDONLY | C.O_CLOEXEC); assert fd >= 0
	assert C.flock(fd, C.LOCK_EX | C.LOCK_NB) == 0
	launch_service_ordinary_failure(service, 'app', 'cannot hold application generation lease')
	C.close(fd)
	mut restored := service.prepare_launch('app')!; restored.close()
	writer := acquire(directory)!; writer.release()
	assert os.read_file(configuration)! == original_config && os.read_file(metadata)! == original_state
	assert os.readlink(directory + '/current')! == 'generations/7'
	$if track_heap ? { println('LAUNCH SERVICE tracked preparation refusals: 1000 attempts per path retained 0 bytes') }
	println('LAUNCH SERVICE root/lock/config/state/ID and missing/FIFO/hard-linked/busy lease refusals retire scratch, preserve files and permit retry PASS')
}

fn launch_service_run_failure(service Service, root bool, cycles int) {
	for mode in 0 .. 5 {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles {
			mut refused := false
			input := LaunchInput{ window: mode == 1, command: mode >= 2, terminal: mode == 3, data_cwd: mode == 4 }
			service.run_mode('app', input) or {
				message := err.msg()
				refused = message == if root { 'run from an ordinary user session, or configure launch_user for the root desktop' }
					else if mode == 1 { 'app: the installed application does not support a native window protocol' }
					else { 'app: permissions blocked by organization policy' }
				unsafe { message.free(); err.free() }
			}
			assert refused
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, 'run retained ' + kept.str() }
	}
	$if track_heap ? { println('LAUNCH SERVICE tracked ' + if root { 'root' } else { 'UID 1000' } + ': five modes, 1000 refusals each retained 0 bytes') }
}

fn test_real_root_service_retires_root_and_ordinary_launch_refusals() {
	// The disposable qualification guest explicitly opts in. Never configure
	// the host's real installation from a normal test invocation.
	if os.getenv('VINIX_LAUNCH_SERVICE_GUEST') != '1' || os.geteuid() != 0 { return }
	assert !os.exists('/etc/vinix-packages') && !os.exists('/var/lib/vinix-packages')
	launch_service_fixture('', launch_service_architecture(), 1)!
	service := Service{}
	launch_service_run_failure(service, true, launch_service_cycles())
	path := '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	blocked := original.replace('"permissions":["files"]', '"permissions":[]')
	assert blocked != original; os.write_file(path, blocked)!
	child := C.fork(); assert child >= 0
	if child == 0 {
		C.alarm(60)
		assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
		os.setenv('HOME', '/home/launch-service-fixture', true)
		launch_service_run_failure(service, false, launch_service_cycles())
		C._exit(0)
	}
	mut status := 0; assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
	assert !os.exists('/home/launch-service-fixture')
	writer := acquire('/var/lib/vinix-packages')!; writer.release()
	println('LAUNCH SERVICE real-root root and UID 1000 runners retire all five launch modes before session/data creation or execution PASS')
}
