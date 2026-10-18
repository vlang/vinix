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
	prefix := root + '/tests/packages/results/2026-10-18/software-dependencies-'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1; verify(ledger.inputs)!; verify(ledger.evidence)!
		println('SOFTWARE DEPENDENCIES retained hashes PASS'); return
	}
	if os.args.len != 4 { return error('usage: software-dependencies-retain HOST_WORK ARM_WORK X86_WORK | --verify') }
	host_work := os.abs_path(os.args[1]); host := json2.decode[Receipt](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.checks.len == 16
	mut inputs := host.inputs.clone(); verify(inputs)!
	mut evidence := []Pin{}
	save(host_work + '/qualification.json', prefix + 'host.json', mut evidence)!
	mut summary := ''
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts
		summary += check.name + ' PASS\n'
		if !check.name.ends_with('-compile') { save(host_work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)! }
	}
	assert os.read_file(host_work + '/ui-functional.txt')!.contains('SOFTWARE DEPENDENCIES shared/cyclic/deep-4096')
	os.write_file(prefix + 'host.txt', summary)!; evidence << pin(prefix + 'host.txt')!
	for i, directory in os.args[2..] {
		work := os.abs_path(directory); architecture := if i == 0 { 'aarch64' } else { 'x86_64' }
		serial := work + '/packages-software-provenance/serial.log'; text := os.read_file(serial)!
		assert text.contains('HWTEST PASS packages-software-provenance') && text.contains('SOFTWARE DEPENDENCIES both hosts')
		assert text.contains('SOFTWARE DEPENDENCIES protocol') && !text.contains('V panic:') && !text.contains('HWTEST FAIL') && !text.contains('Out of memory')
		save(serial, prefix + architecture + '.serial.txt', mut evidence)!
		for path in ['guest/init', 'guest/program-0/view', 'guest/program-1/protocol', 'guest/build.log', 'guest/program-0/build.log', 'guest/program-1/build.log']! {
			inputs << pin(work + '/' + path)!
		}
		inputs << pin(root + '/build/package-software-persistence-work/kernel-' + (if i == 0 { 'arm' } else { 'x86' }) + '/kernel/bin/vinix')!
		inputs << pin(os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!)!
		report := root + '/build/package-software-provenance-work/guest-' + architecture + '-dependencies-1.txt'
		assert os.read_file(report)!.contains('1 passed, 0 failed, 0 skipped')
		save(report, prefix + architecture + '.txt', mut evidence)!
	}
	for architecture in ['arm64', 'amd64']! {
		log := root + '/build/package-software-dependencies-work/desktop-' + architecture + '.txt'
		assert !os.read_file(log)!.contains('error:'); save(log, prefix + 'desktop-' + architecture + '.txt', mut evidence)!
	}
	for path in [@FILE, root + '/tests/packages/software-provenance-runtime-check.v', root + '/tests/packages/software-provenance-guest/main.v',
		root + '/tests/packages/software-dependencies-check.md', root + '/tools/packages/SDK.md', root + '/tools/packages/README.md', root + '/docs/application-distribution.md', root + '/roadmap.md',
		root + '/build/package-software-dependencies-work/desktop.v', root + '/build/package-software-dependencies-work/desktop-check.v', root + '/build/package-software-provenance-work/guest.v',
		root + '/build/package-view-reader-work/desktop/app_calculator.v', root + '/build/package-view-reader-work/desktop/translations_data.v',
		root + '/build/package-software-provenance-work/legacy-media', root + '/build/package-launch-transport-work/cross-cc']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs { if unique.len > 0 && unique.last().path == entry.path { assert unique.last() == entry; continue }; unique << entry }
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{inputs: unique, evidence: evidence}) + '\n')!
	println('SOFTWARE DEPENDENCIES retained ' + unique.len.str() + ' input/artifact hashes and ' + evidence.len.str() + ' evidence hashes PASS')
}

fn main() { retain() or { eprintln(err); exit(1) } }
