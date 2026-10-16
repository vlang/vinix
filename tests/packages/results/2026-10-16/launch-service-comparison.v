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

fn comparison_launch_service_sample(service Service, id string) ! {
	$if launch_service_baseline ? {
		config, state, lease := service.prepare_launch(id)!
		if lease >= 0 { C.close(lease) }
		if state.generation != 0 { close_decoded_state(state) }
		close_decoded_configuration(config)
	} $else { mut prepared := service.prepare_launch(id)!; prepared.close(); prepared.close() }
}
fn comparison_launch_service_attempt(service Service, id string, success bool) {
	mut accepted := true
	comparison_launch_service_sample(service, id) or { accepted = false; message := err.msg(); unsafe { message.free(); err.free() } }
	assert accepted == success
}
fn test_matched_launch_preparation_storage() {
	root := launch_service_root('comparison'); defer { os.rmdir_all(root) or {} }
	service := launch_service_fixture(root, 'aarch64', 1)!
	directory := state_directory(root); configuration := root + '/etc/vinix-packages/config.json'
	metadata := directory + '/generations/7/state.json'; lease := directory + '/generations/7/lease'
	original_config := os.read_file(configuration)!; original_state := os.read_file(metadata)!
	for i in 0 .. 7 {
		if i == 1 { os.write_file(configuration, '{invalid configuration')! }
		if i == 3 { os.write_file(metadata, '{invalid state')! }
		if i == 4 { os.rm(lease)! }
		if i == 5 { os.rm(lease)!; assert C.mkfifo(lease.str, 0o644) == 0 }
		if i == 6 { os.link(lease, lease + '.link')! }
		id := if i == 2 { 'missing' } else { 'app' }
		success := i == 0 || (os.geteuid() == 0 && i >= 2)
		comparison_launch_service_attempt(service, id, success)
		C.vinix_heap_begin()
		for _ in 0 .. 5 { comparison_launch_service_attempt(service, id, success) }
		kept := C.vinix_heap_end()
		println('PREPARE retained ' + i.str() + ' ' + kept.str())
		$if !launch_service_baseline ? { assert kept == 0 }
		if i == 1 { os.write_file(configuration, original_config)! }
		if i == 3 { os.write_file(metadata, original_state)! }
		if i == 4 || i == 5 { if i == 5 { os.rm(lease)! }; os.write_file(lease, '')! }
		if i == 6 { os.rm(lease + '.link')! }
	}
}
