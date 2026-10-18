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

fn require_scopes(text string, native bool) {
	mut count := 0
	mut labels := map[string]bool{}
	for line in text.split_into_lines() {
		if line.starts_with('COLLECTION REQUEST ') && line.ends_with(' tracked bytes') {
			assert line.ends_with(' retained 0 tracked bytes'), line
			label := line.all_before_last(' retained ')
			assert label !in labels, label
			labels[label] = true
			count++
		}
	}
	assert count == 48, count.str()
	for architecture in ['aarch64', 'x86_64']! {
		for kind in ['service', 'explicit']! {
			for mode in ['fresh', 'retained', 'reclaim', 'leased', 'unsafe-root', 'unsafe-stage', 'bad-number',
				'object-directory', 'bad-current', 'bad-previous', 'busy-before-config']! {
				assert 'COLLECTION REQUEST ' + architecture + ' ' + kind + ' ' + mode in labels
			}
		}
		for mode in ['bad-config', 'invalid-root']! { assert 'COLLECTION REQUEST ' + architecture + ' service ' + mode in labels }
	}
	assert text.contains(if native { 'COLLECTION REQUEST 48 selected cases with 8 measured calls each PASS' }
		else { 'COLLECTION REQUEST complete service and explicit calls preserve retained payloads, live leases, recovery refusals and borrowed configuration across 64 calls per case on both declarations PASS' })
}

fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE))); work := root + '/build/package-collection-request-work'
	prefix := root + '/tests/packages/results/2026-10-18/collection-request-'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1; verify(ledger.inputs)!; verify(ledger.evidence)!
		println('COLLECTION REQUEST retained hashes PASS'); return
	}
	if os.args.len != 4 { return error('usage: collection-request-retain HOST_WORK ARM_WORK X86_WORK | --verify') }
	host_work := os.abs_path(os.args[1]); host := json2.decode[Receipt](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.checks.len == 35
	mut inputs := host.inputs.clone(); verify(inputs)!
	mut evidence := []Pin{}
	save(host_work + '/qualification.json', prefix + 'host.json', mut evidence)!
	mut summary := ''
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts; summary += check.name + ' PASS\n'
		if !check.name.ends_with('-compile') { save(host_work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)! }
	}
	for name in ['request-run', 'request-sanitize-run']! { require_scopes(os.read_file(host_work + '/' + name + '.txt')!, false) }
	os.write_file(prefix + 'host.txt', summary)!; evidence << pin(prefix + 'host.txt')!
	for i, directory in os.args[2..] {
		state := os.abs_path(directory); architecture := if i == 0 { 'aarch64' } else { 'x86_64' }
		serial := state + '/packages-collection-request/serial.log'; text := os.read_file(serial)!
		require_scopes(text, true)
		assert text.contains('HWTEST PASS packages-collection-request')
		assert text.contains('COLLECTION RETIREMENT 128 successful removals and 128 refusals retain zero removal-helper allocations PASS')
		assert text.contains('Package collection: 128 obsolete generations under RLIMIT_NOFILE=32; live lease preserved then retired')
		assert !text.contains('V panic:') && !text.contains('HWTEST FAIL') && !text.contains('Out of memory')
		save(serial, prefix + architecture + '.serial.txt', mut evidence)!
		for path in ['guest/init', 'guest/program-0/request', 'guest/program-1/retirement', 'guest/program-2/limit', 'guest/program-3/service',
			'guest/build.log', 'guest/program-0/build.log', 'guest/program-1/build.log', 'guest/program-2/build.log', 'guest/program-3/build.log',
			'guest/program-0/request.c']! { inputs << pin(state + '/' + path)! }
		inputs << pin(root + '/build/package-software-persistence-work/kernel-' + (if i == 0 { 'arm' } else { 'x86' }) + '/kernel/bin/vinix')!
		inputs << pin(os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!)!
		report := work + '/guest-' + architecture + '-5.txt'
		assert os.read_file(report)!.contains('1 passed, 0 failed, 0 skipped'); save(report, prefix + architecture + '.txt', mut evidence)!
	}
	for architecture in ['arm64', 'amd64']! {
		log := work + '/desktop-' + architecture + '.txt'
		assert !os.read_file(log)!.contains('error:'); save(log, prefix + 'desktop-' + architecture + '.txt', mut evidence)!
	}
	baseline := work + '/baseline.txt'; text := os.read_file(baseline)!
	assert text.contains('28668 tracked bytes') && text.contains('21212 tracked bytes') && text.contains('10406 tracked bytes')
	save(baseline, prefix + 'baseline.txt', mut evidence)!
	save(work + '/host-no-space.txt', prefix + 'host-no-space.txt', mut evidence)!
	save(root + '/build/scq-arm-2/packages-collection-request/serial.log', prefix + 'native-64-refusal.serial.txt', mut evidence)!
	save(root + '/build/scq-arm-3/packages-collection-request/serial.log', prefix + 'native-isolated-64-refusal.serial.txt', mut evidence)!
	save(root + '/build/dcq-arm-memory2/packages-collection-request/serial.log', prefix + 'native-memory-diagnostic.serial.txt', mut evidence)!
	save(root + '/build/scq-x86-4/packages-collection-request/serial.log', prefix + 'native-combined-retirement-refusal.serial.txt', mut evidence)!
	for name in ['baseline-service.v.txt', 'baseline-transaction.v.txt', 'baseline-state.v.txt', 'baseline-collection_request_test.v.txt',
		'baseline-before', 'baseline-compile.txt', 'baseline.v', 'prepare.v', 'desktop.v', 'guest.v', 'guest-final', 'host-final', 'guest-controller-final', 'legacy-media',
		'inputs-before-restart.json', 'restart.v', 'reclaim.v', 'pre-isolation-collection_request_test.v.txt',
		'inputs-before-isolation.json', 'host-before-isolation.json', 'prepare-final.v', 'resume-host.v', 'resume-final',
		'debug.v', 'more-debug.v', 'debug-controller.v', 'debug-guest.v', 'debug-source/collection_request_test.v']! { inputs << pin(work + '/' + name)! }
	for path in [root + '/build/scq-arm-2/guest/program-0/request.c', root + '/build/dcq-arm-memory2/guest/program-0/request.c']! { inputs << pin(path)! }
	for path in [@FILE, root + '/tests/packages/collection-request-runtime-check.v', root + '/tests/packages/collection-request-guest/main.v',
		root + '/tests/packages/collection-request-check.md', root + '/tools/packages/SDK.md', root + '/tools/packages/README.md', root + '/docs/application-distribution.md', root + '/roadmap.md',
		root + '/build/package-view-reader-work/desktop/app_calculator.v', root + '/build/package-view-reader-work/desktop/translations_data.v',
		root + '/build/package-launch-transport-work/cross-cc']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs { if unique.len > 0 && unique.last().path == entry.path { assert unique.last() == entry; continue }; unique << entry }
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{inputs: unique, evidence: evidence}) + '\n')!
	println('COLLECTION REQUEST retained ' + unique.len.str() + ' input/artifact hashes and ' + evidence.len.str() + ' evidence hashes PASS')
}

fn main() { retain() or { eprintln(err); exit(1) } }
