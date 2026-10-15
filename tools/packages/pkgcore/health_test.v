// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import encoding.utf8
import os
import time
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn health_fixture() !(string, State) {
	directory := os.temp_dir() + '/vinix-health-report-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	root := directory + '/generations/7'
	os.mkdir_all(root + '/share/applications')!
	mut packages := []Installed{}
	for id in ['runtime', 'app', 'assets', 'utility'] {
		path := root + '/apps/' + id + '/bin/app'
		os.mkdir_all(os.dir(path))!; os.write_file(path, 'payload')!; os.chmod(path, if id == 'assets' { 0o644 } else { 0o755 })!
		p := Package{ id: id, kind: if id == 'assets' { 'data' } else if id == 'runtime' { 'runtime' } else { 'native' },
			name: 'Editor é🚀', version: '1.0.0', architecture: if id == 'assets' { 'all' } else { 'aarch64' }, license: 'MIT',
			entrypoint: 'bin/app', files: [Payload{ path: 'bin/app', bytes: 7, sha256: sha256.hexhash('payload'), executable: id != 'assets' }] }
		packages << Installed{ package: p, repository: 'trusted', public_key: 'a'.repeat(64), sequence: 1 }
		if id in ['app', 'utility'] { os.write_file(root + '/share/applications/vinix-' + id + '.desktop', desktop_entry(p))! }
	}
	return directory, State{ generation: 7, architecture: 'aarch64', packages: packages, requested: ['app', 'utility'] }
}

fn health_damage(directory string) ! {
	root := directory + '/generations/7'
	os.write_file(root + '/apps/app/bin/app', 'damaged')!
	os.rm(root + '/apps/runtime/bin/app')!
	os.write_file(root + '/apps/assets/extra', 'undeclared')!
	os.rm(root + '/share/applications/vinix-utility.desktop')!
}

fn test_health_report_checks_every_package_and_classifies_the_first_own_tree_issue() {
	directory, state := health_fixture()!; defer { os.rmdir_all(directory) or {} }
	mut clean := installed_health_report(directory, state, no_progress)!
	assert clean.rows.len == 4 && clean.rows.all(it.issue == '' && it.diagnostic == '')
	clean.close()
	health_damage(directory)!
	mut damaged := installed_health_report(directory, state, no_progress)!
	assert damaged.rows.map(it.id) == ['app', 'assets', 'runtime', 'utility']
	assert damaged.rows.map(it.issue) == ['payload', 'namespace', 'namespace', 'registration']
	assert damaged.rows.all(it.diagnostic.len > 0 && it.repository == 'trusted')
	assert damaged.rows[0].diagnostic.contains('bin/app')
	damaged.close(); damaged.close()
	assert state.packages[0].package.name == 'Editor é🚀'
	assert os.read_file(directory + '/generations/7/apps/app/bin/app')! == 'damaged'
	mut empty := installed_health_report(directory, State{ architecture: 'aarch64' }, no_progress)!
	assert empty.generation == 0 && empty.rows.len == 0; empty.close()
	println('HEALTH REPORT all app/runtime/data packages inspected, sorted owned provenance, namespace/payload/registration classification, empty state and no filesystem mutation PASS')
}

fn test_health_diagnostics_escape_unsafe_names_and_bound_complete_utf8() {
	for text in ['a\n\r\t\x00\x1b\xffb', 'long é🚀 path '.repeat(100), '\xc2\x80name'] {
		diagnostic := health_diagnostic(text)
		assert utf8.validate_str(diagnostic) && diagnostic.len <= pkgprotocol.health_diagnostic_limit
		assert !diagnostic.bytes().any(it < 32 || it == 127)
		if text.len > 384 { assert diagnostic.ends_with(' [truncated]') }
		else { assert diagnostic.contains('\\x') }
		unsafe { diagnostic.free() }
	}
	println('HEALTH REPORT control/invalid bytes escaped and long UTF-8 diagnostics bounded with truncation disclosure PASS')
}

fn test_health_report_retires_owned_results_and_all_scanner_scratch() {
	$if track_heap ? {
		directory, state := health_fixture()!; defer { os.rmdir_all(directory) or {} }
		for damaged in [false, true]! {
			if damaged { health_damage(directory)! }
			C.vinix_heap_begin()
			for _ in 0 .. 128 {
				mut report := installed_health_report(directory, state, no_progress)!
				assert report.rows.all((it.issue != '') == damaged)
				report.close()
			}
			kept := C.vinix_heap_end(); assert kept == 0, 'health scans (damaged=${damaged}) retained ${kept} bytes'
		}
		println('HEALTH REPORT 128 healthy and 128 multiple-issue scan/retirement cycles retain zero tracked bytes PASS')
	}
}
