// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Host { format int baseline_commit string inputs []Pin checks []Check }
struct Artifact { role string path string sha256 string }
struct Native { format int architecture string seconds f64 artifacts []Artifact }
struct Ledger { format int = 1 baseline_commit string inputs []Pin evidence []Pin }

fn pin(path string) !Pin { return Pin{ path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() } }
fn verify(pins []Pin) ! { for entry in pins { assert pin(entry.path)! == entry, entry.path } }
fn save(source string, destination string, mut pins []Pin) ! { os.cp(source, destination)!; pins << pin(destination)! }

fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	results := root + '/tests/packages/results/2026-10-18'
	ledger_path := results + '/image-integration-ledger.json'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(ledger_path)!)!
		assert ledger.format == 1 && ledger.baseline_commit == '9f86f7ea0'
		verify(ledger.inputs)!; verify(ledger.evidence)!
		println('IMAGE INTEGRATION retained source, compiler, artifact and evidence hashes PASS'); return
	}
	if os.args.len != 4 { return error('usage: image-integration-retain HOST_WORK ARM_WORK X86_WORK | --verify') }
	os.mkdir_all(results)!
	host_work := os.abs_path(os.args[1])
	host := json2.decode[Host](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.baseline_commit == '9f86f7ea0' && host.checks.len == 18
	mut inputs := host.inputs.clone(); verify(inputs)!
	mut evidence := []Pin{}
	save(host_work + '/qualification.json', results + '/image-integration-host.json', mut evidence)!
	mut summary := ''
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts
		summary += check.name + ' PASS\n'
		if check.name.ends_with('-run') || check.name == 'baseline-reproduces' {
			save(host_work + '/' + check.name + '.txt', results + '/image-integration-' + check.name + '.txt', mut evidence)!
		}
	}
	os.write_file(results + '/image-integration-host.txt', summary)!; evidence << pin(results + '/image-integration-host.txt')!
	save(host_work + '/baseline-stage.v', results + '/image-integration-baseline-stage.v', mut evidence)!
	for i, directory in os.args[2..] {
		work := os.abs_path(directory); architecture := if i == 0 { 'aarch64' } else { 'x86_64' }
		native := json2.decode[Native](os.read_file(work + '/qualification.json')!)!
		assert native.format == 1 && native.architecture == architecture && native.artifacts.len == 16
		for artifact in native.artifacts { entry := Pin{ path: artifact.path, sha256: artifact.sha256 }; verify([entry])!; inputs << entry }
		assert native.artifacts.filter(it.role == 'host-stage')[0].sha256 == pin(host_work + '/stage')!.sha256
		serial := os.read_file(work + '/packages-image-integration/serial.log')!
		assert serial.contains('HWTEST PASS packages-image-integration') && serial.contains('IMAGE INTEGRATION 82')
		assert serial.contains('staged licenses/actions/launcher/registration and empty consumer state PASS')
		assert !serial.contains('HWTEST FAIL') && !serial.contains('V panic:') && !serial.contains('Out of memory')
		mut denials := 0
		for line in serial.split_into_lines() {
			if line.starts_with('Denied') { assert line.trim_space().ends_with(': 0'), line; denials++ }
		}
		assert denials == 14
		save(work + '/qualification.json', results + '/image-integration-' + architecture + '.json', mut evidence)!
		save(work + '/packages-image-integration/serial.log', results + '/image-integration-' + architecture + '.serial.txt', mut evidence)!
		save(work + '/stage.log', results + '/image-integration-' + architecture + '.stage.txt', mut evidence)!
		compiler := os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!; inputs << pin(compiler)!
		println(architecture + ' native seconds: ' + native.seconds.str())
	}
	for path in [@FILE, root + '/tests/packages/image-integration-check.md', root + '/tools/packages/SDK.md', root + '/roadmap.md']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs {
		if unique.len > 0 && unique.last().path == entry.path { assert unique.last() == entry; continue }
		unique << entry
	}
	os.write_file(ledger_path, json2.encode(Ledger{ baseline_commit: host.baseline_commit, inputs: unique, evidence: evidence }) + '\n')!
	println('IMAGE INTEGRATION recorded ' + unique.len.str() + ' local input/artifact pins and ' + evidence.len.str() + ' evidence pins PASS')
}

fn main() { retain() or { eprintln(err); exit(1) } }
