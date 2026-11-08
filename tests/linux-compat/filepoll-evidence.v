// SPDX-License-Identifier: GPL-2.0-or-later
// Audit the complete native and Linux receipts without changing historical checkers.
module main

import crypto.sha256
import filepollcheck
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn require(good bool, reason string) ! { if !good { return error(reason) } }
fn check() ! {
	if os.args.len != 2 { return error('Usage: filepoll-evidence BUNDLE') }
	root := os.real_path(os.args[1])
	mut artifacts := map[string]string{}
	for arch in ['aarch64', 'x86_64'] {
		suffix := if arch == 'aarch64' { 'arm' } else { 'x86' }
		compile := root + '/compile-' + suffix + '-r4'
		probe := digest(compile + '/probe')!
		launcher := digest(compile + '/reference-init')!
		build := root + '/build-' + suffix
		kernel := digest(build + '/kernel/bin/vinix')!
		for name in ['receipt.json', 'fixture.c', 'serial.c', 'reference.c', 'probe', 'reference-init'] {
			artifacts[compile + '/' + name] = digest(compile + '/' + name)!
		}
		for name in ['inputs.json', 'outputs.json', 'build.log', 'build.log.command.json', 'kernel/bin/vinix', 'blob.c'] {
			artifacts[build + '/' + name] = digest(build + '/' + name)!
		}
		for linux in [false, true] {
			state := root + '/' + if linux { 'reference-' } else { 'native-' } + suffix + '-r1'
			log := os.read_file(state + '/serial.log')!
			filepollcheck.verify(log, arch, false, linux)!
			receipt := (json2.decode[json2.Any](os.read_file(state + '/receipt.json')!)!).as_map()
			require(receipt['architecture']!.str() == arch, 'Wrong architecture')!
			require(receipt['finished']!.bool() && receipt['passed']!.bool() && receipt['status']!.int() == 0, 'Incomplete guest')!
			if linux {
				pins := receipt['artifacts']!.as_map()
				require(pins['probe']!.str() == probe && pins['wrapper_elf']!.str() == launcher, 'Different Linux probe/launcher')!
				require(pins['kernel']!.str() == digest(state + '/linux')!, 'Different reference kernel')!
				require(pins['serial']!.str() == digest(state + '/serial.log')!, 'Changed reference log')!
			} else {
				require(receipt['probe']!.str() == probe && receipt['kernel']!.str() == kernel, 'Different native probe/kernel')!
				require(digest(state + '/rootfs/sbin/init')! == probe && digest(state + '/kernel/bin/vinix')! == kernel, 'Changed native inputs')!
				require(receipt['serial']!.str() == digest(state + '/serial.log')!, 'Changed native log')!
			}
			for name in ['receipt.json', 'serial.log', 'inputs.json'] { artifacts[state + '/' + name] = digest(state + '/' + name)! }
		}
		baseline := os.read_file(root + '/baseline-' + suffix + '/serial.log')!
		require(baseline.contains('LINUX FILEPOLL SUMMARY: checks=' + if arch == 'aarch64' { '3840 failures=1920' } else { '5120 failures=2560' }), 'Baseline failure changed')!
		require(baseline.contains('LINUX FILEPOLL: FAIL') && !baseline.contains('LINUX FILEPOLL FAIL:'), 'Baseline setup failed')!
		artifacts[root + '/baseline-' + suffix + '/serial.log'] = digest(root + '/baseline-' + suffix + '/serial.log')!
		println('File poll evidence: PASS ' + arch)
	}
	// Keep a checksum manifest next to the full external bundle, never in Git.
	os.write_file(root + '/filepoll-artifacts.json', json2.encode(artifacts, prettify: true) + '\n')!
}
fn main() {
	check() or { eprintln(err.msg()); exit(1) }
}
