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

fn health_fixture() !(string, State, Plan) {
	directory := os.temp_dir() + '/vinix-installed-health-' + os.getpid().str() + '-' + time.now().unix_micro().str()
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

fn health_repairs(directory string, current State, plan Plan, expected []string) {
	repairs := transaction_repairs(directory, current, plan, 'install')
	assert repairs == expected; close_transaction_repairs(repairs)
}

fn health_chmod_checkpoint(phase string, path string) ! {
	if phase == os.file_name(os.dir(path)) { os.chmod(path, 0o644)! }
}

fn test_installed_modes_require_canonical_permissions_without_changing_cache_admission() {
	directory, current, plan := health_fixture()!; defer { os.rmdir_all(directory) or {} }
	app := directory + '/generations/7/apps/app/bin/app'; payload := plan.packages[0].package.files[0]
	health_repairs(directory, current, plan, [])
	for mode in [0o644, 0o775, 0o4755, 0o2755, 0o1755, 0o555] {
		os.chmod(app, mode)!
		// Some host filesystems clear setgid for a group the caller cannot set.
		captured := os.lstat(app)!.mode & 0o7777
		assert verified_file(app, payload) && verified_installed_file(app, payload) == (captured == 0o755)
		health_repairs(directory, current, plan, if captured == 0o755 { []string{} } else { ['app'] })
		assert os.lstat(app)!.mode & 0o7777 == captured
	}
	os.chmod(app, 0o755)!
	data := directory + '/generations/7/apps/data/bin/app'; os.chmod(data, 0o755)!
	health_repairs(directory, current, plan, ['data']); os.chmod(data, 0o644)!
	for phase in ['opened', 'sized', 'block', 'read'] {
		path := directory + '/' + phase + '/app'; os.mkdir_all(os.dir(path))!; os.write_file(path, 'payload')!; os.chmod(path, 0o755)!
		assert !verified_file_with(path, payload, HashReadOptions{ mode: 0o755, checkpoint: health_chmod_checkpoint })
	}
	println('INSTALLATION HEALTH canonical executable/data modes, special bits, captured permission changes and cache isolation PASS')
}

fn test_registration_matches_canonical_signed_metadata_and_refuses_special_files() {
	directory, current, plan := health_fixture()!; defer { os.rmdir_all(directory) or {} }
	generation := directory + '/generations/7'; p := plan.packages[0].package
	entry := generation + '/share/applications/vinix-app.desktop'
	expected := '[Desktop Entry]\nType=Application\nName=Editor é\nComment=Write text\nExec=/usr/bin/vinix-package run app %F\nTerminal=false\nMimeType=text/plain;text/markdown;\nX-Vinix-Package=app\nX-Vinix-Runtime=\n'
	assert desktop_entry(p) == expected && verified_registration(generation, p)
	assert desktop_entry(Package{ ...p, associations: [] }).contains('MimeType=;\n')
	assert verified_registration(generation, plan.packages[1].package) && verified_registration(generation, plan.packages[2].package)
	for mode in [0o600, 0o755, 0o4644] { os.chmod(entry, mode)!; health_repairs(directory, current, plan, ['app']) }
	os.chmod(entry, 0o644)!
	outside := directory + '/outside'; os.write_file(outside, expected)!; os.chmod(outside, 0o644)!
	for kind in ['missing', 'symlink', 'fifo', 'directory', 'changed', 'oversized'] {
		if os.is_dir(entry) { os.rmdir(entry)! } else if os.exists(entry) || os.is_link(entry) { os.rm(entry)! }
		match kind {
			'symlink' { os.symlink(outside, entry)! }
			'fifo' { assert C.mkfifo(entry.str, 0o644) == 0 }
			'directory' { os.mkdir(entry)! }
			'changed' { os.write_file(entry, 'x'.repeat(expected.len))!; os.chmod(entry, 0o644)! }
			'oversized' { os.write_file(entry, expected + 'extra')!; os.chmod(entry, 0o644)! }
			else {}
		}
		assert !verified_registration(generation, p); health_repairs(directory, current, plan, ['app'])
	}
	assert os.read_file(outside)! == expected && os.lstat(outside)!.mode & 0o7777 == 0o644
	println('INSTALLATION HEALTH canonical launcher/MIME bytes, independent runtime/data, permissions/type/content refusal and unchanged outside files PASS')
}

fn test_installed_health_discovery_retires_all_owned_scratch() {
	$if track_heap ? {
		directory, current, plan := health_fixture()!; defer { os.rmdir_all(directory) or {} }
		entry := directory + '/generations/7/share/applications/vinix-app.desktop'
		for damaged in [false, true] {
			if damaged { os.rm(entry)! }
			C.vinix_heap_begin()
			for _ in 0 .. 64 {
				repairs := transaction_repairs(directory, current, plan, 'install')
				assert repairs.len == if damaged { 1 } else { 0 }; close_transaction_repairs(repairs)
			}
			kept := C.vinix_heap_end(); assert kept == 0 && C.vinix_heap_count() == 0, 'installed health retained ${kept} bytes'
		}
		println('INSTALLATION HEALTH 128 healthy/registration-damaged discovery cycles retain zero tracked bytes PASS')
	}
}
