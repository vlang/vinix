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
fn verify(pins []Pin) ! { for item in pins { assert pin(item.path)! == item, item.path } }
fn save(source string, target string, mut evidence []Pin) ! { os.cp(source, target)!; evidence << pin(target)! }
fn scopes(text string, prefix string, count int, baseline bool) {
	mut labels := map[string]bool{}
	for line in text.split_into_lines() {
		if !line.starts_with(prefix + ' ') || !line.ends_with(' tracked bytes') { continue }
		label := line.all_before_last(' retained '); assert label !in labels, label; labels[label] = true
		if !baseline { assert line.ends_with(' retained 0 tracked bytes'), line }
	}
	assert labels.len == count, prefix
	if prefix == 'HTTPS OWNER' {
		for kind in ['fresh', 'resumed']! {
			for mode in ['full', 'no-range', 'empty', 'partial', 'oversized', 'failure', 'terminated', 'missing-program',
				'offline', 'insecure', 'nul', 'alias', 'directory', 'fifo', 'hardlink', 'flush-interrupted', 'flush-failure', 'flush-link']! {
				assert prefix + ' ' + mode + ' ' + kind in labels
			}
			for phase in ['opened', 'written', 'finished', 'start', 'finish']! {
				for mutation in ['alias', 'grow']! { assert prefix + ' change-' + phase + '-' + mutation + ' ' + kind in labels }
			}
		}
		assert prefix + ' prefix-limit resumed' in labels
	} else {
		for mode in ['fetch-fresh', 'fetch-resume', 'fetch-fallback', 'fetch-truncated', 'fetch-http', 'fetch-redirect', 'fetch-untrusted', 'fetch-hostname', 'fetch-size']! {
			assert prefix + ' ' + mode in labels
		}
		for arch in ['aarch64', 'x86_64']! {
			for mode in ['refresh-fresh', 'refresh-untrusted', 'refresh-hostname', 'refresh-signature', 'install-fresh', 'install-resume',
				'install-fallback', 'install-bad-prefix', 'install-truncated', 'install-http', 'install-redirect', 'install-corrupt', 'install-untrusted', 'install-hostname']! {
				assert prefix + ' ' + arch + ' ' + mode in labels
			}
		}
	}
}
fn field(line string, name string) !u64 {
	for part in line.fields() { if part.starts_with(name + '=') { return strconv.parse_uint(part.all_after('='), 10, 64) } }
	return error('missing counter ' + name)
}
fn counters(text string) ! {
	mut ceiling := u64(0); mut count := 0
	for line in text.split_into_lines() {
		if line.starts_with('HTTPS OWNER file baseline=') { ceiling = field(line, 'ceiling')!; assert ceiling == field(line, 'baseline')! + 131072 }
		if line.starts_with('COLLECTION STRESS settled ') { assert ceiling != 0 && field(line, 'bytes')! <= ceiling && field(line, 'waits')! <= 30; count++ }
	}
	assert count == 2
}
fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE))); work := root + '/build/package-https-owner-work'
	prefix := root + '/tests/packages/results/2026-10-18/https-owner-'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1; verify(ledger.inputs)!; verify(ledger.evidence)!
		println('HTTPS OWNER retained hashes PASS'); return
	}
	assert os.args.len == 4, 'usage: https-owner-retain HOST_WORK ARM_WORK X86_WORK | --verify'
	host_work := os.abs_path(os.args[1]); host := json2.decode[Receipt](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.checks.len == 22
	mut inputs := host.inputs.clone(); verify(inputs)!; mut evidence := []Pin{}; mut summary := ''
	save(host_work + '/qualification.json', prefix + 'host.json', mut evidence)!
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts; summary += check.name + ' PASS\n'
		if check.name.ends_with('-run') { save(host_work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)! }
	}
	for name in ['owner-untracked', 'owner-tracked', 'owner-sanitize']! {
		text := os.read_file(host_work + '/' + name + '-run.txt')!; scopes(text, 'HTTPS OWNER', 57, false)
		assert text.contains('HTTPS OWNER 57 cases with 64 measured calls preserve bytes, bounded retries, output guards and child/descriptor retirement PASS')
	}
	for name in ['live', 'live-sanitize']! {
		text := os.read_file(host_work + '/' + name + '-run.txt')!; scopes(text, 'HTTPS LIVE', 37, false)
		assert text.contains('HTTPS LIVE 37 cases with 64 measured calls preserve authenticated state, TLS policy, bounded recovery and independent replies PASS')
		for file in ['requests.txt', 'certificate.cnf', 'ca.pem', 'certificate.txt', 'untrusted/ca.pem']! {
			inputs << pin(host_work + '/' + name + '-tls/' + file)!
		}
		save(host_work + '/' + name + '-tls/requests.txt', prefix + name + '-requests.txt', mut evidence)!
	}
	os.write_file(prefix + 'host.txt', summary)!; evidence << pin(prefix + 'host.txt')!
	for i, directory in os.args[2..] {
		state := os.abs_path(directory); arch := if i == 0 { 'aarch64' } else { 'x86_64' }
		serial := state + '/packages-https-owner/serial.log'; text := os.read_file(serial)!
		scopes(text, 'HTTPS OWNER', 57, false); counters(text)!
		for marker in ['HWTEST PASS packages-https-owner', 'HTTPS DIAGNOSTICS 41 exit statuses', 'HTTPS DIAGNOSTICS 1000 cycles', 'HTTPS GUARD 72', 'HTTPS GUARD 96']! { assert text.contains(marker), marker }
		assert !text.contains('HWTEST FAIL') && !text.contains('V panic:') && !text.contains('Out of memory')
		save(serial, prefix + arch + '.serial.txt', mut evidence)!
		save(state + '/packages-https-owner/qemu.log', prefix + arch + '.qemu.txt', mut evidence)!
		for path in ['guest/init', 'guest/init.c', 'guest/build.log']! { inputs << pin(state + '/' + path)! }
		for index, name in ['owner', 'core', 'producer']! { for suffix in [name, name + '.c', 'build.log'] { inputs << pin(state + '/guest/program-' + index.str() + '/' + suffix)! } }
		inputs << pin(root + '/build/package-software-persistence-work/kernel-' + (if i == 0 { 'arm' } else { 'x86' }) + '/kernel/bin/vinix')!
		inputs << pin(os.find_abs_path_of_executable(arch + '-linux-musl-gcc')!)!
		report := work + '/guest-' + arch + '-1.txt'; assert os.read_file(report)!.contains('1 passed, 0 failed, 0 skipped')
		save(report, prefix + arch + '.txt', mut evidence)!
	}
	baseline := os.read_file(work + '/baseline.txt')!; scopes(baseline, 'HTTPS OWNER', 57, true)
	assert baseline.contains('HTTPS OWNER full fresh retained 158 tracked bytes') && baseline.contains('HTTPS OWNER no-range resumed retained 626 tracked bytes')
	save(work + '/baseline.txt', prefix + 'baseline.txt', mut evidence)!
	for path in os.walk_ext(work + '/before', '.v') { inputs << pin(path)! }
	for name in ['before-runner', 'before.c', 'prepare.v', 'prepare-host.v', 'prepare-checks.v', 'host-owner.v.txt', 'host-live.v.txt',
		'run.v', 'capture', 'guest.v', 'guest-final', 'guest-controller-final', 'host-final', 'legacy-media']! { inputs << pin(work + '/' + name)! }
	for path in os.walk_ext(root + '/tests/hardware-platform/hwhost', '.v') { if !path.ends_with('_test.v') { inputs << pin(path)! } }
	for path in os.walk_ext(root + '/tests/packages/collectionstress', '.v') { if !path.ends_with('_test.v') { inputs << pin(path)! } }
	for path in [@FILE, root + '/tests/packages/https-owner-runtime-check.v', root + '/tests/packages/https-owner-guest/main.v',
		root + '/tests/packages/https-owner-check.md', root + '/roadmap.md', root + '/tools/packages/SDK.md', root + '/tools/packages/README.md',
		root + '/docs/application-distribution.md', root + '/build/package-launch-transport-work/cross-cc']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for item in inputs { if unique.len > 0 && unique.last().path == item.path { assert unique.last() == item; continue }; unique << item }
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{inputs: unique, evidence: evidence}) + '\n')!
	println('HTTPS OWNER retained ' + unique.len.str() + ' input/artifact hashes and ' + evidence.len.str() + ' evidence hashes PASS')
}
fn main() { retain() or { eprintln(err); exit(1) } }
