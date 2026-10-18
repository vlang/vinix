// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Receipt { format int inputs []Pin checks []Check }
struct Ledger { format int = 1 inputs []Pin evidence []Pin }

fn pin(path string) !Pin { return Pin{path: path, sha256: sha256.sum(os.read_bytes(path)!).hex()} }
fn verify(pins []Pin) ! { for entry in pins { assert pin(entry.path)! == entry, entry.path } }
fn save(source string, destination string, mut evidence []Pin) ! { os.cp(source, destination)!; evidence << pin(destination)! }

fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	prefix := root + '/tests/packages/results/2026-10-18/software-progress-memory-'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1; verify(ledger.inputs)!; verify(ledger.evidence)!
		println('SOFTWARE PROGRESS retained hashes PASS'); return
	}
	if os.args.len != 3 { return error('usage: software-progress-memory-retain HOST_WORK BASELINE_WORK | --verify') }
	host_work := os.abs_path(os.args[1]); host := json2.decode[Receipt](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.checks.len == 10
	mut inputs := host.inputs.clone(); verify(inputs)!
	mut evidence := []Pin{}
	save(host_work + '/qualification.json', prefix + 'host.json', mut evidence)!
	mut summary := ''
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts
		summary += check.name + ' PASS\n'
		if !check.name.ends_with('-compile') { save(host_work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)! }
	}
	for name in ['ui-memory', 'ui-sanitize-memory']! {
		assert os.read_file(host_work + '/' + name + '.txt')!.contains('SOFTWARE PROGRESS 12 x 1000')
	}
	os.write_file(prefix + 'host.txt', summary)!; evidence << pin(prefix + 'host.txt')!
	baseline := os.abs_path(os.args[2])
	assert os.read_file(baseline + '/baseline-run.txt')!.contains('message: progress case 0 retained 32000 bytes')
	// Retain the exact old handler, not a reconstruction of the missing free.
	mut child := os.new_process('git'); child.set_args(['-C', root, 'show', 'ab6911db7:desktop/software_progress.v']); child.set_redirect_stdio_merged()
	child.run(); old := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	assert code == 0 && old == os.read_file(baseline + '/software/software_progress.v')!
	for path in os.walk_ext(baseline + '/software', '.v') { inputs << pin(path)! }
	for path in ['baseline', 'quick.v']! { inputs << pin(baseline + '/' + path)! }
	for name in ['baseline-compile', 'baseline-run']! {
		save(baseline + '/' + name + '.txt', prefix + name + '.txt', mut evidence)!
	}
	save(baseline + '/software/software_progress.v', prefix + 'before.v', mut evidence)!
	save(baseline + '/software/software_progress_memory_fixture.v', prefix + 'before-fixture.v', mut evidence)!
	for architecture in ['arm64', 'amd64']! {
		log := baseline + '/desktop-' + architecture + '.txt'
		assert !os.read_file(log)!.contains('error:'); save(log, prefix + 'desktop-' + architecture + '.txt', mut evidence)!
	}
	for path in [@FILE, root + '/tests/packages/distribution-check.v', root + '/tests/packages/software-progress-memory-check.md',
		root + '/tools/packages/SDK.md', root + '/tools/packages/README.md', root + '/docs/application-distribution.md', root + '/roadmap.md',
		baseline + '/desktop.v', root + '/build/package-view-reader-work/desktop/app_calculator.v',
		root + '/build/package-view-reader-work/desktop/translations_data.v']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs { if unique.len > 0 && unique.last().path == entry.path { assert unique.last() == entry; continue }; unique << entry }
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{inputs: unique, evidence: evidence}) + '\n')!
	println('SOFTWARE PROGRESS retained ' + unique.len.str() + ' input/artifact hashes and ' + evidence.len.str() + ' evidence hashes PASS')
}

fn main() { retain() or { eprintln(err); exit(1) } }
