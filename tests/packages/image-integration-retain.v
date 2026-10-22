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
fn verify(pins []Pin) ! {
	for entry in pins { if pin(entry.path)! != entry { return error('input/artifact digest mismatch: ' + entry.path) } }
}
fn save(source string, destination string, mut pins []Pin) ! { os.cp(source, destination)!; pins << pin(destination)! }

// Preflight and publication use the same explicit checks. In particular, -prod
// must never disable admission by compiling away assertions.
fn retain(publish bool) ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	results := if os.args.len == 6 { os.abs_path(os.args[5]) } else { root + '/tests/packages/results/2026-10-18' }
	ledger_path := results + '/image-integration-ledger.json'
	if os.args.len in [2, 3] && os.args[1] == '--verify' {
		if publish { return }
		ledger := json2.decode[Ledger](os.read_file(if os.args.len == 3 { os.args[2] } else { ledger_path })!)!
		if ledger.format != 1 || ledger.baseline_commit != '9f86f7ea0' { return error('unsupported image integration ledger') }
		verify(ledger.inputs)!; verify(ledger.evidence)!
		println('IMAGE INTEGRATION retained source, compiler, artifact and evidence hashes PASS'); return
	}
	if os.args.len !in [4, 6] || (os.args.len == 6 && os.args[4] != '--output') {
		return error('usage: image-integration-retain HOST_WORK ARM_WORK X86_WORK [--output NEW_DIRECTORY] | --verify [LEDGER]')
	}
	if !publish && os.args.len == 6 && (os.exists(results) || os.is_link(results)) { return error('output directory must be new') }
	if publish { os.mkdir_all(results)! }
	host_work := os.abs_path(os.args[1])
	host := json2.decode[Host](os.read_file(host_work + '/qualification.json')!)!
	if host.format != 1 || host.baseline_commit != '9f86f7ea0' || host.checks.len != 18 { return error('unsupported or incomplete host qualification') }
	mut inputs := host.inputs.clone(); verify(inputs)!
	mut evidence := []Pin{}
	if publish { save(host_work + '/qualification.json', results + '/image-integration-host.json', mut evidence)! }
	mut summary := ''
	mut seen := map[string]bool{}
	names := ['stage-compile', 'compiler-compile', 'cli-compile', 'tools-cli-compile', 'cli-run', 'tools-cli-run',
		'image_integration-compile', 'image_integration-run', 'sanitize-compile', 'sanitize-run', 'image_tools-compile',
		'image_tools-run', 'image_configuration-compile', 'image_configuration-run', 'atomic_new-compile', 'atomic_new-run',
		'baseline-compile', 'baseline-reproduces']
	for check in host.checks {
		if check.name !in names || check.name in seen { return error('missing or duplicated host check: ' + check.name) }
		seen[check.name] = true
		verify(check.artifacts)!; inputs << check.artifacts
		summary += check.name + ' PASS\n'
		if publish && (check.name.ends_with('-run') || check.name == 'baseline-reproduces') {
			save(host_work + '/' + check.name + '.txt', results + '/image-integration-' + check.name + '.txt', mut evidence)!
		}
	}
	if publish {
		os.write_file(results + '/image-integration-host.txt', summary)!; evidence << pin(results + '/image-integration-host.txt')!
		save(host_work + '/baseline-stage.v', results + '/image-integration-baseline-stage.v', mut evidence)!
	}
	for i, directory in os.args[2..4] {
		work := os.abs_path(directory); architecture := if i == 0 { 'aarch64' } else { 'x86_64' }
		native := json2.decode[Native](os.read_file(work + '/qualification.json')!)!
		if native.format != 1 || native.architecture != architecture || native.artifacts.len != 16 { return error('unsupported or incomplete native qualification: ' + architecture) }
		for artifact in native.artifacts { entry := Pin{ path: artifact.path, sha256: artifact.sha256 }; verify([entry])!; inputs << entry }
		stagers := native.artifacts.filter(it.role == 'host-stage')
		if stagers.len != 1 || stagers[0].sha256 != pin(host_work + '/stage')!.sha256 { return error('native host stager differs: ' + architecture) }
		serial_artifacts := native.artifacts.filter(it.role == 'serial-log')
		if serial_artifacts.len != 1 || serial_artifacts[0].sha256 != pin(work + '/packages-image-integration/serial.log')!.sha256 { return error('native serial artifact differs: ' + architecture) }
		serial := os.read_file(work + '/packages-image-integration/serial.log')!
		for marker in ['HWTEST START packages-image-integration', 'HWTEST PASS packages-image-integration',
			'IMAGE INTEGRATION 82 source/capture/publication/refusal cases preserve overrides and outside data; stable descriptors PASS',
			'IMAGE INTEGRATION native staged licenses/actions/launcher/registration and empty consumer state PASS',
			'IMAGE INTEGRATION native production-staged package/session/Linux-runner execution PASS'] {
			if serial.split_into_lines().filter(it == marker).len != 1 { return error('missing or duplicated exact serial marker: ' + marker) }
		}
		for marker in ['HWTEST FAIL', 'V panic:', 'Out of memory', 'Kernel panic'] {
			if serial.contains(marker) { return error('forbidden serial marker: ' + marker) }
		}
		mut denials := 0
		for line in serial.split_into_lines() {
			if line.starts_with('Denied') { if !line.trim_space().ends_with(': 0') { return error('nonzero denial counter: ' + line) }; denials++ }
		}
		if denials != 14 { return error('incomplete denial counters: ' + architecture) }
		if publish {
			save(work + '/qualification.json', results + '/image-integration-' + architecture + '.json', mut evidence)!
			save(work + '/packages-image-integration/serial.log', results + '/image-integration-' + architecture + '.serial.txt', mut evidence)!
			save(work + '/stage.log', results + '/image-integration-' + architecture + '.stage.txt', mut evidence)!
		}
		compiler := os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!; inputs << pin(compiler)!
		if publish { println(architecture + ' native seconds: ' + native.seconds.str()) }
	}
	for path in [@FILE, root + '/tests/packages/image-integration-check.md', root + '/tools/packages/SDK.md', root + '/roadmap.md']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs {
		if unique.len > 0 && unique.last().path == entry.path { if unique.last() != entry { return error('conflicting input digests: ' + entry.path) }; continue }
		unique << entry
	}
	if !publish { return }
	os.write_file(ledger_path, json2.encode(Ledger{ baseline_commit: host.baseline_commit, inputs: unique, evidence: evidence }) + '\n')!
	println('IMAGE INTEGRATION recorded ' + unique.len.str() + ' local input/artifact pins and ' + evidence.len.str() + ' evidence pins PASS')
}

fn main() { retain(false) or { eprintln(err); exit(1) }; retain(true) or { eprintln(err); exit(1) } }
