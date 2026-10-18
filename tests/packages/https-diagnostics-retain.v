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
	root := os.dir(os.dir(os.dir(@FILE))); prefix := root + '/tests/packages/results/2026-10-18/https-diagnostics-'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1; verify(ledger.inputs)!; verify(ledger.evidence)!
		println('HTTPS DIAGNOSTICS retained hashes PASS'); return
	}
	if os.args.len != 4 { return error('usage: https-diagnostics-retain HOST_WORK ARM_WORK X86_WORK | --verify') }
	work := os.abs_path(os.args[1]); host := json2.decode[Receipt](os.read_file(work + '/qualification.json')!)!
	assert host.format == 1 && host.checks.len == 12
	mut inputs := host.inputs.clone(); verify(inputs)!
	mut evidence := []Pin{}; mut summary := ''
	save(work + '/qualification.json', prefix + 'host.json', mut evidence)!
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts; summary += check.name + ' PASS\n'
		if check.name.ends_with('-run') { save(work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)! }
	}
	assert os.read_file(work + '/tls-run.txt')!.contains('HTTPS DIAGNOSTICS real TLS')
	os.write_file(prefix + 'host.txt', summary)!; evidence << pin(prefix + 'host.txt')!
	for i, directory in os.args[2..] {
		native := os.abs_path(directory); architecture := if i == 0 { 'aarch64' } else { 'x86_64' }
		serial := native + '/packages-https-diagnostics/serial.log'; output := os.read_file(serial)!
		for marker in ['HWTEST PASS packages-https-diagnostics', 'HTTPS DIAGNOSTICS 41 exit statuses', 'HTTPS DIAGNOSTICS 1000 cycles', 'HTTPS GUARD 72', 'HTTPS GUARD 96']! { assert output.contains(marker) }
		assert !output.contains('HWTEST FAIL') && !output.contains('V panic:') && !output.contains('Out of memory')
		save(serial, prefix + architecture + '.serial.txt', mut evidence)!
		for path in ['guest/init', 'guest/program-0/core', 'guest/program-1/producer', 'guest/build.log', 'guest/program-0/build.log', 'guest/program-1/build.log']! { inputs << pin(native + '/' + path)! }
		inputs << pin(root + '/build/package-software-persistence-work/kernel-' + (if i == 0 { 'arm' } else { 'x86' }) + '/kernel/bin/vinix')!
		inputs << pin(os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!)!
		report := root + '/build/package-https-diagnostics-work/guest-' + architecture + '-2.txt'
		assert os.read_file(report)!.contains('1 passed, 0 failed, 0 skipped'); save(report, prefix + architecture + '.txt', mut evidence)!
	}
	for path in [@FILE, root + '/tests/packages/https-diagnostics-runtime-check.v', root + '/tests/packages/https-diagnostics-guest/main.v',
		root + '/tests/packages/https-diagnostics-check.md', root + '/tools/packages/SDK.md', root + '/tools/packages/README.md', root + '/docs/application-distribution.md', root + '/roadmap.md',
		root + '/build/package-https-diagnostics-work/guest.v', root + '/build/package-https-diagnostics-work/legacy-media', root + '/build/package-launch-transport-work/cross-cc']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs { if unique.len > 0 && unique.last().path == entry.path { assert unique.last() == entry; continue }; unique << entry }
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{inputs: unique, evidence: evidence}) + '\n')!
	println('HTTPS DIAGNOSTICS retained ' + unique.len.str() + ' input/artifact and ' + evidence.len.str() + ' evidence hashes PASS')
}

fn main() { retain() or { eprintln(err); exit(1) } }
