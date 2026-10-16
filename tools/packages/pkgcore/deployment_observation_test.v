// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn observation_fixture(count int) Plan {
	mut packages := []Installed{cap: count}
	mut roots := []string{cap: count}
	for index in 0 .. count {
		id := 'app-' + index.str()
		p := Package{ id: id, name: id, version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
			permissions: ['files'], files: [Payload{ path: 'data/file', sha256: 'a'.repeat(64), bytes: 7 }] }
		packages << Installed{ package: p, repository: 'publisher', public_key: 'b'.repeat(64), sequence: 7 }
		roots << id
	}
	return Plan{ requested: roots, packages: packages }
}

fn test_deployment_observations_retire_owned_documents_and_audit_scratch() {
	$if track_heap ? {
		plan := observation_fixture(16)
		mut expected := owned_deployment_lock('aarch64', plan)!
		defer { expected.close() }
		digest := 'c'.repeat(64)
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut document := owned_deployment_lock('aarch64', plan)!
			text := encode_deployment_lock(document, true)!
			encoded_digest := index_digest(text)
			unsafe { text.free(); encoded_digest.free() }
			document.close()
		}
		owned_bytes := C.vinix_heap_end()
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut audit := compare_deployment(expected, expected, 7, digest)!
			audit.close()
		}
		audit_bytes := C.vinix_heap_end()
		println('Deployment observation: 1000 16-package export/encode/hash cycles retained ${owned_bytes} bytes; 1000 comparisons retained ${audit_bytes} bytes')
		assert owned_bytes == 0 && audit_bytes == 0
	}
}

fn test_deployment_encoding_preserves_exact_json_owned_fields_and_inclusive_file_size_bound() {
	plan := observation_fixture(16)
	mut document := owned_deployment_lock('aarch64', plan)!
	defer { document.close() }
	expected := json2.encode(document)
	for newline in [false, true]! {
		text := encode_deployment_lock(document, newline)!
		assert text == expected + if newline { '\n' } else { '' }
		mut decoded := decode_deployment(text, 'aarch64')!
		assert decoded == document && decoded.locked.len == 16
		decoded.close()
		unsafe { text.free() }
	}
	// Isolate the encoder's byte bound from semantic/schema admission. An
	// artificial long architecture fills exactly the remaining JSON capacity.
	base := encode_deployment_lock(DeploymentLock{}, false)!
	padding := 'x'.repeat(max_metadata - base.len)
	boundary := DeploymentLock{ architecture: padding }
	$if track_heap ? { C.vinix_heap_begin() }
	full := encode_deployment_lock(boundary, false)!
	assert full.len == max_metadata
	unsafe { full.free() }
	if _ := encode_deployment_lock(boundary, true) { assert false } else {
		message := err.msg(); assert message.contains('metadata limit'); unsafe { message.free(); err.free() }
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	unsafe { base.free(); padding.free() }
	assert plan.packages[0].package.id == 'app-0' && plan.packages[0].package.files[0].path == 'data/file'
	println('Deployment observation: exact SDK JSON and optional LF; inclusive metadata bound and overflow refusal release growth buffers PASS')
}

fn test_deployment_observation_limits_preserve_complete_owned_records_and_union() {
	plan := observation_fixture(4096)
	mut document := owned_deployment_lock('x86_64', plan)!
	defer { document.close() }
	assert document.packages.len == 4096 && document.locked.len == 4096 && document.locked[0].id == 'app-0'
	mut roots := []string{cap: 4096}
	mut pins := []DeploymentPackage{cap: 4096}
	for pin in document.locked {
		id := 'other-' + pin.id
		roots << id
		pins << DeploymentPackage{ ...pin, id: id }
	}
	mut audit := compare_deployment(document, DeploymentLock{ architecture: 'x86_64', packages: roots, locked: pins }, 9, 'd'.repeat(64))!
	defer { audit.close() }
	assert audit.rows.len == 8192 && !audit.matches
	assert audit.rows.filter(it.status == 'missing').len == 4096 && audit.rows.filter(it.status == 'unexpected').len == 4096
	assert document.locked[4095].id == plan.packages.map(it.package.id).sorted()[4095]
	println('Deployment observation: complete 4096-root/record snapshots and 8192-row disjoint audit union PASS')
}

fn test_installed_deployment_plan_borrows_manifests_and_retires_selection_scratch() {
	plan := observation_fixture(16)
	state := State{ requested: plan.requested, packages: plan.packages }
	names := ['app-0', 'app-15']
	missing := ['app-0', 'not-installed']
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		selected := installed_deployment_plan(state, names)!
		assert selected.requested == names && selected.packages.len == 2
		assert selected.packages[0].package.files.data == state.packages[0].package.files.data
		assert selected.packages[1].package.files.data == state.packages[15].package.files.data
		mut owned := owned_deployment_lock('aarch64', selected)!
		unsafe { for root in selected.requested { root.free() }; (&array(&selected.requested)).free(); (&array(&selected.packages)).free() }
		assert owned.locked[0].id == 'app-0' && owned.locked[1].id == 'app-15'
		owned.close()
		if _ := installed_deployment_plan(state, missing) { assert false } else {
			message := err.msg(); assert message.contains('not installed'); unsafe { message.free(); err.free() }
		}
	}
	$if track_heap ? { kept := C.vinix_heap_end(); println('Deployment observation: 1000 borrowed selections, owned snapshots and missing-root refusals retained ${kept} bytes'); assert kept == 0 }
	assert state.packages[15].package.id == 'app-15' && state.packages[0].package.files[0].path == 'data/file'
	println('Deployment observation: selected manifests borrow source state; exported records survive selection-buffer retirement PASS')
}

fn test_public_snapshot_save_and_audit_observations_preserve_owned_results_and_store() {
	work := os.real_path(os.temp_dir()) + '/vinix-observation-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	defer { os.rmdir_all(work) or {} }
	os.mkdir_all(work + '/etc/vinix-packages')!
	config := Config{ architecture: 'aarch64', policy: Policy{ offline: true, allowed: ['other'], permissions: [], reserve_bytes: 0 } }
	config_text := json2.encode(config)
	os.write_file(work + '/etc/vinix-packages/config.json', config_text)!
	store := state_directory(work)
	guard := acquire(store)!; guard.release()
	plan := observation_fixture(4)
	state := State{ architecture: config.architecture, generation: 7, requested: plan.requested, packages: plan.packages }
	state_text := encode_generation_state(state)!
	os.mkdir(store + '/generations/7')!
	os.write_file(store + '/generations/7/state.json', state_text)!
	os.symlink('generations/7', store + '/current')!
	os.write_file(store + '/catalog.json', '{unavailable catalog')!
	os.write_file(store + '/trust-history.json', '{unavailable history')!
	service := Service{ root: work }
	path := work + '/saved é; $literal.json'
	mut warmup := service.snapshot_deployment([])!; warmup.close()
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 100 {
		mut document := service.snapshot_deployment([])!
		assert document.packages.len == 4 && document.locked.len == 4
		document.close(); document.close()
		mut saved := service.save_deployment_snapshot(path, [])!
		assert saved.generation == 7 && saved.packages == 4 && saved.roots == 4
		saved.close(); saved.close()
		mut audit := service.audit_deployment(path)!
		assert audit.matches && audit.rows.len == 4 && audit.generation == 7
		audit.close(); audit.close()
		if _ := service.save_deployment_snapshot(path, []) { assert false } else {
			message := err.msg(); assert message.contains('already exists'); unsafe { message.free(); err.free() }
		}
		os.rm(path)!
	}
	$if track_heap ? { kept := C.vinix_heap_end(); println('Deployment observation: 100 public snapshot/save/audit and existing-file refusal cycles retained ${kept} bytes'); assert kept == 0 }
	assert os.read_file(store + '/current/state.json')! == state_text && os.readlink(store + '/current')! == 'generations/7'
	assert os.read_file(work + '/etc/vinix-packages/config.json')! == config_text
	assert os.read_file(store + '/catalog.json')! == '{unavailable catalog' && os.read_file(store + '/trust-history.json')! == '{unavailable history'
	assert os.ls(store + '/objects')!.len == 0 && os.ls(store + '/generations')! == ['7']
	assert os.ls(work)!.all(!it.starts_with('.package-'))
	println('Deployment observation: public owned snapshots, durable saved receipts, exact offline audits and existing-file refusals preserve store PASS')
}
