// SPDX-License-Identifier: GPL-2.0-or-later
// Audit the complete native and Linux receipts without changing historical checkers.
module main

import crypto.sha256
import epollfilecheck
import filepollcheck
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn require(good bool, reason string) ! { if !good { return error(reason) } }
fn native_receipt(state string, arch string, kernel string, probe string) ! {
	receipt := (json2.decode[json2.Any](os.read_file(state + '/receipt.json')!)!).as_map()
	require(receipt['architecture']!.str() == arch && receipt['kernel']!.str() == kernel
		&& receipt['probe']!.str() == probe, 'Different regression input')!
	require(receipt['finished']!.bool() && receipt['passed']!.bool() && receipt['status']!.int() == 0, 'Incomplete regression')!
	require(receipt['serial']!.str() == digest(state + '/serial.log')!, 'Changed regression log')!
}
fn maskwait(text string) ! {
	mut wanted := map[string]int{}
	for ordinary in 0 .. 2 { for signal in [10, 12] { for kind in 0 .. 6 { for mode in 0 .. 4 {
		checks := 11 + (if mode == 1 { 3 } else { 0 }) + (if kind in [1, 2, 3, 4] { 2 } else { 0 })
		line := 'LINUX MASKWAIT CASE: uid=' + if ordinary == 0 { '0 gid=0' } else { '1000 gid=2000' }
			+ ' signal=' + signal.str() + ' wait=' + kind.str() + ' mode=' + mode.str() + ' checks=' + checks.str() + ' failures=0'
		wanted[line] = 1
	} } } }
	wanted['LINUX MASKWAIT SUMMARY: checks=1256 failures=0'] = 1
	wanted['LINUX MASKWAIT: PASS'] = 1
	mut actual := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX MASKWAIT') { actual[line]++ }
	}
	require(actual == wanted, 'Incomplete masked-wait regression')!
}
fn check() ! {
	if os.args.len != 2 { return error('Usage: epollfile-evidence BUNDLE') }
	root := os.real_path(os.args[1])
	mut artifacts := map[string]string{}
	for arch in ['aarch64', 'x86_64'] {
		suffix := if arch == 'aarch64' { 'arm' } else { 'x86' }
		compile := root + '/compile-epoll-' + suffix + '-r2'
		probe := digest(compile + '/probe')!
		launcher := digest(compile + '/reference-init')!
		build := root + '/build-epoll-' + suffix + '-r4'
		kernel := digest(build + '/kernel/bin/vinix')!
		generated := os.read_file(build + '/blob.c')!
		for name in ['fs__ProcFSResource', 'fs__SysFSResource', 'fs__CGroupResource', 'file__MemoryPressureFile',
			'fs__CGroupPressureFile', 'proc__PidFile', 'drm__GemPrimeResource', 'userland__SignalFD'] {
			require(generated.contains(name + '__poll_status('), 'Missing generated callback: ' + name)!
		}
		for name in ['receipt.json', 'fixture.c', 'serial.c', 'reference.c', 'probe', 'reference-init'] {
			artifacts[compile + '/' + name] = digest(compile + '/' + name)!
		}
		for name in ['inputs.json', 'outputs.json', 'build.log', 'build.log.command.json', 'kernel/bin/vinix', 'blob.c'] {
			artifacts[build + '/' + name] = digest(build + '/' + name)!
		}
		for linux in [false, true] {
			state := root + '/' + if linux { 'reference-epoll-' } else { 'native-epoll-' } + suffix + '-r1'
			log := os.read_file(state + '/serial.log')!
			epollfilecheck.verify(log, arch, false, linux)!
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
		baseline := os.read_file(root + '/baseline-epoll-' + suffix + '-r1/serial.log')!
		require(baseline.contains('LINUX EPOLLFILE SUMMARY: checks=' + '6720 failures=4160'), 'Baseline failure changed')!
		require(baseline.contains('LINUX EPOLLFILE: FAIL') && !baseline.contains('LINUX EPOLLFILE FAIL:'), 'Baseline setup failed')!
		artifacts[root + '/baseline-epoll-' + suffix + '-r1/serial.log'] = digest(root + '/baseline-epoll-' + suffix + '-r1/serial.log')!
		async_state := root + '/native-async-' + suffix + '-r1'
		async_probe := digest(root + '/compile-async-' + suffix + '-r2/probe')!
		native_receipt(async_state, arch, kernel, async_probe)!
		async_log := os.read_file(async_state + '/serial.log')!
		async_records := async_log.split_into_lines().map(it.trim_space()).filter(it.starts_with('LINUX POLLASYNC'))
		require(async_records == ['LINUX POLLASYNC CASE: vmpressure PASS', 'LINUX POLLASYNC CASE: cgroup PASS',
			'LINUX POLLASYNC CASE: virtual-files PASS', 'LINUX POLLASYNC CASE: pidfd PASS',
			'LINUX POLLASYNC SUMMARY: cases=4 failures=0', 'LINUX POLLASYNC: PASS'], 'Asynchronous readiness regression failed')!
		for label in ['filepoll', 'maskwait'] {
			state := root + '/regression-' + label + '-' + suffix + '-final'
			log := os.read_file(state + '/serial.log')!
			for bad in ['FAIL', 'MISMATCH', 'KERNEL PANIC', 'FATAL EXCEPTION'] { require(!log.contains(bad), 'Regression failure: ' + bad)! }
			probe_hash := if label == 'filepoll' { digest(root + '/compile-' + suffix + '-r4/probe')! }
				else { digest(state + '/rootfs/sbin/init')! }
			native_receipt(state, arch, kernel, probe_hash)!
			if label == 'filepoll' { filepollcheck.verify(log, arch, false, false)! } else { maskwait(log)! }
			for name in ['receipt.json', 'serial.log', 'inputs.json'] { artifacts[state + '/' + name] = digest(state + '/' + name)! }
		}
		for name in ['receipt.json', 'serial.log', 'inputs.json'] { artifacts[async_state + '/' + name] = digest(async_state + '/' + name)! }
		println('Epoll file and asynchronous readiness evidence: PASS ' + arch)
	}
	// Keep a checksum manifest next to the full external bundle, never in Git.
	os.write_file(root + '/epollfile-artifacts.json', json2.encode(artifacts, prettify: true) + '\n')!
}
fn main() {
	check() or { eprintln(err.msg()); exit(1) }
}
