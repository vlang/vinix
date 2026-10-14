// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.mkfifo(&char, u32) int

fn repair_fixture() !(string, State, Plan) {
	directory := os.temp_dir() + '/vinix-repair-core-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	text := 'expected installed bytes'
	mut packages := []Installed{}
	for id in ['runtime', 'app', 'data'] {
		os.mkdir_all(directory + '/generations/7/apps/' + id + '/bin')!
		os.write_file(directory + '/generations/7/apps/' + id + '/bin/app', text)!
		packages << Installed{ repository: 'trusted', public_key: 'a'.repeat(64), sequence: 1,
			package: Package{ id: id, kind: 'data', architecture: 'all', name: id, version: '1.0.0', license: 'MIT',
				files: [Payload{ path: 'bin/app', bytes: u64(text.len), sha256: sha256.sum(text.bytes()).hex() }] } }
	}
	return directory, State{ generation: 7, architecture: 'aarch64', requested: ['app'], packages: packages }, Plan{ packages: packages }
}

fn assert_no_repairs(directory string, current State, plan Plan, operation string) {
	repairs := transaction_repairs(directory, current, plan, operation)
	assert repairs.len == 0
	close_transaction_repairs(repairs)
}

fn test_repairs_require_unchanged_target_provenance_and_signed_payloads_from_the_active_generation() {
	directory, current, plan := repair_fixture()!
	defer { os.rmdir_all(directory) or {} }
	path := directory + '/generations/7/apps/app/bin/app'
	assert_no_repairs(directory, current, plan, 'install')
	os.write_file(path, 'x'.repeat(24))!
	for operation in ['install', 'upgrade', 'deploy'] {
		repairs := transaction_repairs(directory, current, plan, operation)
		assert repairs == ['app']; close_transaction_repairs(repairs)
	}
	for operation in ['remove', 'rollback', 'mirror'] { assert_no_repairs(directory, current, plan, operation) }
	assert_no_repairs(directory, State{}, plan, 'install')
	changed := Plan{ packages: plan.packages.map(if it.package.id == 'app' {
		Installed{ ...it, package: Package{ ...it.package, version: '2.0.0' } }
	} else { it }) }
	assert_no_repairs(directory, current, changed, 'install')
	rotated := Plan{ packages: plan.packages.map(if it.package.id == 'app' { Installed{ ...it, public_key: 'b'.repeat(64) } } else { it }) }
	assert_no_repairs(directory, current, rotated, 'install')
	for kind in ['missing', 'symlink', 'fifo', 'directory'] {
		if os.is_dir(path) { os.rmdir(path)! } else if os.exists(path) || os.is_link(path) { os.rm(path)! }
		match kind {
			'symlink' { os.symlink(directory + '/generations/7/apps/data/bin/app', path)! }
			'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			'directory' { os.mkdir(path)! }
			else {}
		}
		repairs := transaction_repairs(directory, current, plan, 'install')
		assert repairs == ['app']; close_transaction_repairs(repairs)
	}
	os.rm(directory + '/generations/7/apps/runtime/bin/app')!
	repairs := transaction_repairs(directory, current, plan, 'upgrade')
	assert repairs == ['app', 'runtime']; close_transaction_repairs(repairs)
	println('PACKAGE REPAIR active payload hash/size/type, changed-target exclusion, sorted closure and removal/rollback isolation PASS')
}

fn test_repair_discovery_retires_its_owned_paths_maps_and_ids() {
	$if track_heap ? {
		directory, current, plan := repair_fixture()!
		defer { os.rmdir_all(directory) or {} }
		path := directory + '/generations/7/apps/app/bin/app'
		for damaged in [false, true] {
			if damaged { os.write_file(path, 'damaged bytes')! }
			C.vinix_heap_begin()
			for _ in 0 .. 64 {
				repairs := transaction_repairs(directory, current, plan, 'install')
				assert repairs.len == if damaged { 1 } else { 0 }
				close_transaction_repairs(repairs)
			}
			kept := C.vinix_heap_end()
			assert kept == 0 && C.vinix_heap_count() == 0, 'repair discovery retained ${kept} bytes'
		}
		println('PACKAGE REPAIR 128 healthy/damaged discovery and retirement cycles retain zero tracked bytes PASS')
	}
}
