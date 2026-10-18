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

fn require_scopes(text string, native bool) {
	mut labels := map[string]bool{}
	for line in text.split_into_lines() {
		if !line.starts_with('COLLECTION REQUEST ') || !line.ends_with(' tracked bytes') { continue }
		assert line.ends_with(' retained 0 tracked bytes'), line
		label := line.all_before_last(' retained '); assert label !in labels, label; labels[label] = true
	}
	assert labels.len == 48
	for architecture in ['aarch64', 'x86_64']! {
		for kind in ['service', 'explicit']! {
			for mode in ['fresh', 'retained', 'reclaim', 'leased', 'unsafe-root', 'unsafe-stage', 'bad-number',
				'object-directory', 'bad-current', 'bad-previous', 'busy-before-config']! {
				assert 'COLLECTION REQUEST ' + architecture + ' ' + kind + ' ' + mode in labels
			}
		}
		for mode in ['bad-config', 'invalid-root']! { assert 'COLLECTION REQUEST ' + architecture + ' service ' + mode in labels }
	}
	assert text.contains(if native { 'COLLECTION STRESS 48 cases with 64 measured calls after 8 warmups PASS' }
		else { 'COLLECTION REQUEST complete service and explicit calls preserve retained payloads, live leases, recovery refusals and borrowed configuration across 64 calls per case on both declarations PASS' })
}

fn numeric_field(line string, name string) !u64 {
	for field in line.fields() { if field.starts_with(name + '=') { return strconv.parse_uint(field.all_after('='), 10, 64) } }
	return error('missing retained numeric field ' + name)
}

fn require_retirement(text string) ! {
	mut ceiling := u64(0); mut settled := 0; mut waited := false
	for line in text.split_into_lines() {
		if line.starts_with('COLLECTION STRESS file baseline=') {
			baseline := numeric_field(line, 'baseline')!; ceiling = numeric_field(line, 'ceiling')!
			assert baseline <= ~u64(0) - 131072 && ceiling == baseline + 131072
		}
		if line.starts_with('COLLECTION STRESS settled ') {
			assert ceiling != 0 && numeric_field(line, 'bytes')! <= ceiling, line
			waits := numeric_field(line, 'waits')!; assert waits <= 30; waited = waited || waits > 0
			settled++
		}
	}
	assert settled == 56 && waited
	for marker in ['unsafe root preserves all generations', 'changed parent refuses even with unchanged generation',
		'ten changed nested/ancestor directories preserve data', 'ten post-inventory root/lease replacements refuse',
		'128-generation batch, 64-level tree, 1024 long-name files and 128 success/refusal loops',
		'128 successful removals and 128 refusals retain zero removal-helper allocations PASS',
		'COLLECTION STRESS all six retirement cases in separate processes PASS',
		'Package collection: 128 obsolete generations under RLIMIT_NOFILE=32; live lease preserved then retired']! { assert text.contains(marker), marker }
}

fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE))); work := root + '/build/package-collection-stress-work'
	prefix := root + '/tests/packages/results/2026-10-18/collection-stress-'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1; verify(ledger.inputs)!; verify(ledger.evidence)!
		println('COLLECTION STRESS retained hashes PASS'); return
	}
	if os.args.len != 4 { return error('usage: collection-stress-retain HOST_WORK ARM_WORK X86_WORK | --verify') }
	host_work := os.abs_path(os.args[1]); host := json2.decode[Receipt](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.checks.len == 14
	mut inputs := host.inputs.clone(); verify(inputs)!
	mut evidence := []Pin{}; save(host_work + '/qualification.json', prefix + 'host.json', mut evidence)!
	mut summary := ''
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts; summary += check.name + ' PASS\n'
		if !check.name.ends_with('-compile') { save(host_work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)! }
	}
	for name in ['request-run', 'request-sanitize-run', 'stress-run', 'stress-sanitize-run']! { require_scopes(os.read_file(host_work + '/' + name + '.txt')!, false) }
	os.write_file(prefix + 'host.txt', summary)!; evidence << pin(prefix + 'host.txt')!
	for i, directory in os.args[2..] {
		state := os.abs_path(directory); architecture := if i == 0 { 'aarch64' } else { 'x86_64' }
		serial := state + '/packages-collection-stress/serial.log'; text := os.read_file(serial)!
		require_scopes(text, true); require_retirement(text)!
		assert text.contains('HWTEST PASS packages-collection-stress') && !text.contains('HWTEST FAIL')
		assert !text.contains('V panic:') && !text.contains('Out of memory')
		save(serial, prefix + architecture + '.serial.txt', mut evidence)!
		save(state + '/packages-collection-stress/qemu.log', prefix + architecture + '.qemu.txt', mut evidence)!
		for path in ['guest/init', 'guest/init.c', 'guest/build.log']! { inputs << pin(state + '/' + path)! }
		for index in 0 .. 9 {
			name := if index == 0 { 'request' } else if index < 7 { 'retirement-' + (index - 1).str() } else if index == 7 { 'limit' } else { 'service' }
			for suffix in [name, name + '.c', 'build.log'] { inputs << pin(state + '/guest/program-' + index.str() + '/' + suffix)! }
		}
		inputs << pin(root + '/build/package-software-persistence-work/kernel-' + (if i == 0 { 'arm' } else { 'x86' }) + '/kernel/bin/vinix')!
		inputs << pin(os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!)!
		report := work + '/guest-' + architecture + '-1.txt'
		assert os.read_file(report)!.contains('1 passed, 0 failed, 0 skipped'); save(report, prefix + architecture + '.txt', mut evidence)!
	}
	baseline := root + '/build/scs-arm-1/packages-collection-request/serial.log'
	assert os.read_file(baseline)!.contains('LastDeniedOwnerBytes: 59725956')
	save(baseline, prefix + 'budget-denial.serial.txt', mut evidence)!
	save(work + '/guest-aarch64-1-probe.txt', prefix + 'budget-denial.txt', mut evidence)!
	drain := root + '/build/scs-arm-drain/packages-collection-request/serial.log'; drained := os.read_file(drain)!
	assert drained.contains('DRAIN SAMPLE 1') && drained.contains('file 154 921390') && drained.contains('file 148 884448')
	save(drain, prefix + 'budget-drain.serial.txt', mut evidence)!
	save(work + '/guest-aarch64-drain.txt', prefix + 'budget-drain.txt', mut evidence)!
	for name in ['prepare-probe.v', 'prepare-drain.v', 'probe-before-drain.v.txt', 'probe-source/collection_request_test.v',
		'probe-controller.v', 'probe-controller', 'probe-guest/main.v', 'guest.v', 'final-guest.v', 'guest-final', 'host-final',
		'guest-controller-final', 'prepare-public.v', 'legacy-media', 'reclaim.v']! { inputs << pin(work + '/' + name)! }
	for path in [@FILE, root + '/build/scs-arm-1/guest/program-0/request.c', root + '/build/scs-arm-drain/guest/program-0/request.c',
		root + '/build/package-collection-request-work/pre-isolation-collection_request_test.v.txt', root + '/build/package-launch-transport-work/cross-cc',
		root + '/tests/packages/collection-stress-check.md', root + '/tests/packages/collection-request-check.md', root + '/roadmap.md']! { inputs << pin(path)! }
	for path in os.walk_ext(root + '/tests/hardware-platform/hwhost', '.v') {
		if !path.ends_with('_test.v') { inputs << pin(path)! }
	}
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs { if unique.len > 0 && unique.last().path == entry.path { assert unique.last() == entry; continue }; unique << entry }
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{inputs: unique, evidence: evidence}) + '\n')!
	println('COLLECTION STRESS retained ' + unique.len.str() + ' input/artifact hashes and ' + evidence.len.str() + ' evidence hashes PASS')
}

fn main() { retain() or { eprintln(err); exit(1) } }
