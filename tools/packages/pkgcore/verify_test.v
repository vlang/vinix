// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn verify_fixture() !(string, State, Plan) {
	directory := os.temp_dir() + '/vinix-verify-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	generation := directory + '/generations/7'
	os.mkdir_all(generation + '/share/applications')!
	mut packages := []Installed{}
	for id in ['app', 'runtime', 'data'] {
		path := generation + '/apps/' + id + '/bin/app'
		os.mkdir_all(os.dir(path))!; os.write_file(path, 'payload')!; os.chmod(path, if id == 'data' { 0o644 } else { 0o755 })!
		p := Package{ id: id, kind: if id == 'app' { 'native' } else { id }, name: 'Editor é', description: 'Write text',
			architecture: if id == 'data' { 'all' } else { 'aarch64' }, version: '1.0.0', license: 'MIT', entrypoint: 'bin/app',
			associations: ['text/plain', 'text/markdown'], files: [Payload{ path: 'bin/app', bytes: 7, sha256: sha256.hexhash('payload'), executable: id != 'data' }] }
		packages << Installed{ package: p, repository: 'trusted', public_key: 'a'.repeat(64), sequence: 1 }
		if id == 'app' { os.write_file(generation + '/share/applications/vinix-app.desktop', desktop_entry(p))!; os.chmod(generation + '/share/applications/vinix-app.desktop', 0o644)! }
	}
	return directory, State{ generation: 7, architecture: 'aarch64', requested: ['app'], packages: packages }, Plan{ packages: packages }
}

fn verify_record(event pkgprotocol.Progress) {
	event.validate() or { panic(err) }
	mut file := os.open_file(os.getenv('VINIX_VERIFY_LOG'), 'a', 0o600) or { panic(err) }
	defer { file.close() }
	file.writeln(json2.encode(event)) or { panic(err) }
}

fn verify_events(path string) ![]pkgprotocol.Progress {
	mut events := []pkgprotocol.Progress{}
	for line in os.read_file(path)!.split_into_lines() { events << pkgprotocol.decode_progress(line)! }
	return events
}

fn test_verify_reports_payload_and_registration_work_and_completes_only_a_healthy_scan() {
	directory, state, _ := verify_fixture()!; defer { os.rmdir_all(directory) or {} }
	log := directory + '/events'; os.setenv('VINIX_VERIFY_LOG', log, true); defer { os.unsetenv('VINIX_VERIFY_LOG') }
	os.write_file(log, '')!; verify_installed(directory, state, verify_record)!
	events := verify_events(log)!
	assert events.len == 6 && events.first().phase == 'verify' && events.first().package == ''
	assert events.filter(it.phase == 'verify' && it.path == 'bin/app').map(it.package) == ['app', 'runtime', 'data']
	assert events.any(it.path == 'share/applications/vinix-app.desktop' && it.package == 'app')
	assert events.last().phase == 'complete' && events.last().current == 1 && events.last().total == 1
	for kind in ['payload', 'mode', 'registration'] {
		app := directory + '/generations/7/apps/app/bin/app'
		entry := directory + '/generations/7/share/applications/vinix-app.desktop'
		if kind == 'payload' { os.write_file(app, 'damaged')! }
		if kind == 'mode' { os.chmod(app, 0o644)! }
		if kind == 'registration' { os.rm(entry)! }
		os.write_file(log, '')!
		if _ := verify_installed(directory, state, verify_record) { assert false }
		else { assert err.msg().contains('verification failed') && err.msg().contains('vinix-package repair') }
		failed := verify_events(log)!
		assert failed.all(it.phase == 'verify')
		if kind == 'mode' {
			// Namespace admission refuses unsafe modes before payload hashing.
			assert failed.len == 1 && failed[0].package == ''
		} else {
			assert failed.len >= 2
			assert failed.last().path == if kind == 'registration' { 'share/applications/vinix-app.desktop' } else { 'bin/app' }
		}
		os.write_file(app, 'payload')!; os.chmod(app, 0o755)!
		if kind == 'registration' { os.write_file(entry, desktop_entry(state.packages[0].package))!; os.chmod(entry, 0o644)! }
	}
	os.write_file(log, '')!; verify_installed(directory, State{}, verify_record)!
	assert verify_events(log)!.map(it.phase) == ['verify', 'complete']
	println('VERIFY PROGRESS payload/launcher identity, compatible counters, empty state and no completion on byte/mode/registration failure PASS')
}

fn test_repeated_verify_scan_retires_owned_scratch() {
	$if track_heap ? {
		directory, state, _ := verify_fixture()!; defer { os.rmdir_all(directory) or {} }
		entry := directory + '/generations/7/share/applications/vinix-app.desktop'
		for damaged in [false, true] {
			if damaged { os.rm(entry)! }
			C.vinix_heap_begin()
			for _ in 0 .. 64 {
				mut failed := false
				verify_installed(directory, state, no_progress) or {
					failed = true; message := err.msg(); unsafe { message.free(); err.free() }
				}
				assert failed == damaged
			}
			kept := C.vinix_heap_end(); assert kept == 0 && C.vinix_heap_count() == 0, 'verify scan retained ${kept} bytes'
		}
		println('VERIFY PROGRESS 128 healthy/failed scans retain zero tracked bytes PASS')
	}
}
