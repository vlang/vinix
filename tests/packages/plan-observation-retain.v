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

fn require_scopes(text string) {
	mut count := 0
	for line in text.split_into_lines() {
		if line.starts_with('PLAN OBSERVATION ') && line.contains(' retained ') {
			assert line.ends_with(' retained 0 tracked bytes'), line
			count++
		}
	}
	assert count == 98, count.str()
	assert text.contains('PLAN OBSERVATION complete service and explicit previews preserve independent manifests, exact JSON and signed state across 64 calls per case on both declarations PASS')
	assert text.contains('PLAN OBSERVATION 33-package nested copies preserve every field, full-width numbers and independent retirement across 1000 cycles per architecture PASS')
}

fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE))); work := root + '/build/package-plan-observation-work'
	prefix := root + '/tests/packages/results/2026-10-18/plan-observation-'
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1; verify(ledger.inputs)!; verify(ledger.evidence)!
		println('PLAN OBSERVATION retained hashes PASS'); return
	}
	if os.args.len != 4 { return error('usage: plan-observation-retain HOST_WORK ARM_WORK X86_WORK | --verify') }
	host_work := os.abs_path(os.args[1]); host := json2.decode[Receipt](os.read_file(host_work + '/qualification.json')!)!
	assert host.format == 1 && host.checks.len == 34
	mut inputs := host.inputs.clone(); verify(inputs)!
	mut evidence := []Pin{}
	save(host_work + '/qualification.json', prefix + 'host.json', mut evidence)!
	mut summary := ''
	for check in host.checks {
		verify(check.artifacts)!; inputs << check.artifacts; summary += check.name + ' PASS\n'
		if !check.name.ends_with('-compile') { save(host_work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)! }
	}
	for name in ['plan-run', 'plan-sanitize-run']! { require_scopes(os.read_file(host_work + '/' + name + '.txt')!) }
	os.write_file(prefix + 'host.txt', summary)!; evidence << pin(prefix + 'host.txt')!
	for i, directory in os.args[2..] {
		state := os.abs_path(directory); architecture := if i == 0 { 'aarch64' } else { 'x86_64' }
		serial := state + '/packages-plan-observation/serial.log'; text := os.read_file(serial)!
		require_scopes(text)
		assert text.contains('HWTEST PASS packages-plan-observation') && text.contains('1000 public successful multi-version installs')
		assert !text.contains('V panic:') && !text.contains('HWTEST FAIL') && !text.contains('Out of memory')
		save(serial, prefix + architecture + '.serial.txt', mut evidence)!
		for path in ['guest/init', 'guest/program-0/plan', 'guest/program-1/preference', 'guest/program-2/service', 'guest/program-3/empty',
			'guest/build.log', 'guest/program-0/build.log', 'guest/program-1/build.log', 'guest/program-2/build.log', 'guest/program-3/build.log']! { inputs << pin(state + '/' + path)! }
		inputs << pin(root + '/build/package-software-persistence-work/kernel-' + (if i == 0 { 'arm' } else { 'x86' }) + '/kernel/bin/vinix')!
		inputs << pin(os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!)!
		report := work + '/guest-' + architecture + '-1.txt'
		assert os.read_file(report)!.contains('1 passed, 0 failed, 0 skipped'); save(report, prefix + architecture + '.txt', mut evidence)!
	}
	for architecture in ['arm64', 'amd64']! {
		log := work + '/desktop-' + architecture + '.txt'
		assert !os.read_file(log)!.contains('error:'); save(log, prefix + 'desktop-' + architecture + '.txt', mut evidence)!
	}
	baseline := work + '/baseline.txt'; text := os.read_file(baseline)!
	assert text.contains('87486 tracked bytes') && text.contains('79744 tracked bytes') && text.contains('7742 tracked bytes')
	save(baseline, prefix + 'baseline.txt', mut evidence)!
	save(work + '/host-no-space.txt', prefix + 'host-no-space.txt', mut evidence)!
	for name in ['baseline-review.v.txt', 'baseline-service.v.txt', 'baseline-main.v.txt', 'baseline-plan_observation_test.v.txt',
		'baseline-before', 'baseline-compile.txt', 'baseline.v', 'prepare.v', 'desktop.v', 'guest.v', 'guest-final', 'host-final', 'guest-controller-final', 'legacy-media',
		'inputs-before-resume.json', 'prepare-resume.v', 'resume-host.v', 'resume-final']! { inputs << pin(work + '/' + name)! }
	for path in [@FILE, root + '/tests/packages/plan-observation-runtime-check.v', root + '/tests/packages/plan-observation-guest/main.v',
		root + '/tests/packages/plan-observation-check.md', root + '/tools/packages/SDK.md', root + '/tools/packages/README.md', root + '/docs/application-distribution.md', root + '/roadmap.md',
		root + '/build/package-view-reader-work/desktop/app_calculator.v', root + '/build/package-view-reader-work/desktop/translations_data.v',
		root + '/build/package-launch-transport-work/cross-cc']! { inputs << pin(path)! }
	inputs.sort(a.path < b.path); mut unique := []Pin{}
	for entry in inputs { if unique.len > 0 && unique.last().path == entry.path { assert unique.last() == entry; continue }; unique << entry }
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{inputs: unique, evidence: evidence}) + '\n')!
	println('PLAN OBSERVATION retained ' + unique.len.str() + ' input/artifact hashes and ' + evidence.len.str() + ' evidence hashes PASS')
}

fn main() { retain() or { eprintln(err); exit(1) } }
