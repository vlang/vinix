// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import strconv

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Receipt { format int inputs []Pin checks []Check }
struct Ledger { format int = 1 inputs []Pin evidence []Pin }

fn pin(path string) !Pin { return Pin{path: path, sha256: sha256.sum(os.read_bytes(path)!).hex()} }
fn verify(pins []Pin) ! { for entry in pins { assert pin(entry.path)! == entry, entry.path } }
fn save(source string, destination string, mut evidence []Pin) ! { os.cp(source, destination)!; evidence << pin(destination)! }

fn require_scopes(text string, baseline bool) {
	mut labels := map[string]bool{}
	for line in text.split_into_lines() {
		if !line.starts_with('REFRESH REQUEST ') || !line.ends_with(' tracked bytes') { continue }
		if !baseline { assert line.ends_with(' retained 0 tracked bytes'), line }
		label := line.all_before_last(' retained '); assert label !in labels, label; labels[label] = true
	}
	assert labels.len == 72
	for architecture in ['aarch64', 'x86_64']! {
		for kind in ['service', 'explicit']! {
			for mode in ['fresh', 'cached', 'migrate', 'empty', 'bad-cache', 'bad-history', 'signature', 'syntax', 'schema',
				'expired', 'floor', 'equivocation', 'ambiguous', 'missing-index', 'missing-signature', 'offline', 'busy']! {
				assert 'REFRESH REQUEST ' + architecture + ' ' + kind + ' ' + mode in labels
			}
		}
		for mode in ['bad-config', 'invalid-root']! { assert 'REFRESH REQUEST ' + architecture + ' service ' + mode in labels }
	}
}

fn controls(text string) {
	for marker in ['REFRESH REQUEST independently owned publisher identities and nested manifests survive configuration and sibling reply retirement PASS',
		'REFRESH WORKSPACE captured stale nested work retires; aliases and writable work preserve metadata and foreign files PASS',
		'REFRESH PUBLICATION trust-history 64 refused calls retained 0 tracked bytes PASS',
		'REFRESH PUBLICATION catalog 64 refused calls retained 0 tracked bytes PASS']! { assert text.contains(marker), marker }
}

fn field(line string, name string) !u64 {
	for part in line.fields() { if part.starts_with(name + '=') { return strconv.parse_uint(part.all_after('='), 10, 64) } }
	return error('missing numeric observation ' + name)
}

fn settled(text string) ! {
	mut ceiling := u64(0); mut count := 0; mut waited := false
	for line in text.split_into_lines() {
		if line.starts_with('REFRESH REQUEST file baseline=') {
			baseline := field(line, 'baseline')!; ceiling = field(line, 'ceiling')!
			assert baseline <= ~u64(0) - 131072 && ceiling == baseline + 131072
		}
		if line.starts_with('COLLECTION STRESS settled ') {
			assert ceiling != 0 && field(line, 'bytes')! <= ceiling
			waits := field(line, 'waits')!; assert waits <= 30; waited = waited || waits > 0; count++
		}
	}
	assert count == 76 && waited
}

fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE))); work := root + '/build/package-refresh-request-work'
	prefix := root + '/tests/packages/results/2026-10-18/refresh-request-'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1; verify(ledger.inputs)!; verify(ledger.evidence)!
		println('REFRESH REQUEST retained hashes PASS'); return
	}
	if os.args.len != 4 { return error('usage: refresh-request-retain HOST_WORK ARM_WORK X86_WORK | --verify') }
	host_work := os.abs_path(os.args[1]); host := json2.decode[Receipt](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.checks.len == 35
	mut inputs := host.inputs.clone(); verify(inputs)!; mut evidence := []Pin{}
	save(host_work + '/qualification.json', prefix + 'host.json', mut evidence)!
	mut summary := ''
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts; summary += check.name + ' PASS\n'
		if !check.name.ends_with('-compile') { save(host_work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)! }
	}
	for name in ['request-untracked-run', 'request-run', 'request-sanitize-run']! {
		text := os.read_file(host_work + '/' + name + '.txt')!; require_scopes(text, false); controls(text)
		assert text.contains('REFRESH REQUEST 72 service and explicit cases preserve signed metadata, lock order and owned replies across 64 measured calls PASS')
	}
	os.write_file(prefix + 'host.txt', summary)!; evidence << pin(prefix + 'host.txt')!
	for i, directory in os.args[2..] {
		state := os.abs_path(directory); architecture := if i == 0 { 'aarch64' } else { 'x86_64' }
		serial := state + '/packages-refresh-request/serial.log'; text := os.read_file(serial)!
		require_scopes(text, false); controls(text); settled(text)!
		assert text.contains('HWTEST PASS packages-refresh-request') && !text.contains('HWTEST FAIL')
		assert text.contains('REFRESH REQUEST 72 cases with 64 measured calls after 8 warmups PASS')
		assert !text.contains('V panic:') && !text.contains('Out of memory')
		save(serial, prefix + architecture + '.serial.txt', mut evidence)!
		save(state + '/packages-refresh-request/qemu.log', prefix + architecture + '.qemu.txt', mut evidence)!
		for path in ['guest/init', 'guest/init.c', 'guest/build.log']! { inputs << pin(state + '/' + path)! }
		for index, name in ['request', 'lifetime', 'workspace', 'service', 'copy']! {
			for suffix in [name, name + '.c', 'build.log'] { inputs << pin(state + '/guest/program-' + index.str() + '/' + suffix)! }
		}
		inputs << pin(root + '/build/package-software-persistence-work/kernel-' + (if i == 0 { 'arm' } else { 'x86' }) + '/kernel/bin/vinix')!
		inputs << pin(os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!)!
		report := work + '/guest-' + architecture + '-1.txt'
		assert os.read_file(report)!.contains('1 passed, 0 failed, 0 skipped'); save(report, prefix + architecture + '.txt', mut evidence)!
	}
	baseline := os.read_file(work + '/baseline.txt')!; require_scopes(baseline, true)
	assert baseline.contains('aarch64 service fresh retained 13784 tracked bytes') && baseline.contains('aarch64 explicit fresh retained 5878 tracked bytes')
	save(work + '/baseline.txt', prefix + 'baseline.txt', mut evidence)!
	for name in ['before-runner', 'before-main.v.txt', 'prepare.v', 'prepare-checks.v', 'run.v', 'capture', 'guest.v', 'guest-final',
		'guest-controller-final', 'host-final', 'legacy-media']! { inputs << pin(work + '/' + name)! }
	for path in os.walk_ext(work + '/before', '.v') { inputs << pin(path)! }
	for path in os.walk_ext(root + '/tests/hardware-platform/hwhost', '.v') { if !path.ends_with('_test.v') { inputs << pin(path)! } }
	for path in [@FILE, root + '/build/package-launch-transport-work/cross-cc', root + '/roadmap.md', root + '/tools/packages/README.md',
		root + '/tools/packages/SDK.md', root + '/docs/application-distribution.md', root + '/tests/packages/refresh-request-check.md']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs { if unique.len > 0 && unique.last().path == entry.path { assert unique.last() == entry; continue }; unique << entry }
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{inputs: unique, evidence: evidence}) + '\n')!
	println('REFRESH REQUEST retained ' + unique.len.str() + ' input/artifact hashes and ' + evidence.len.str() + ' evidence hashes PASS')
}

fn main() { retain() or { eprintln(err); exit(1) } }
