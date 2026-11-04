// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn require(good bool, message string) ! { if !good { return error(message) } }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn expected(baseline bool) []string {
	mut lines := []string{}
	for ordinary in 0 .. 2 { for signal in [10, 12] { for kind in 0 .. 6 { for mode in 0 .. 4 {
		checks := 11 + (if mode == 1 { 3 } else { 0 }) + (if kind in [1, 2, 3, 4] { 2 } else { 0 })
		failures := if baseline && kind != 5 { if mode == 1 { 5 } else { 1 } } else { 0 }
		lines << 'LINUX MASKWAIT CASE: uid=' + if ordinary == 0 { '0 gid=0' } else { '1000 gid=2000' }
			+ ' signal=' + signal.str() + ' wait=' + kind.str() + ' mode=' + mode.str()
			+ ' checks=' + checks.str() + ' failures=' + failures.str()
		if failures > 0 {
			for stage in if mode == 1 { [14, 16, 18, 19, 20] } else { [16] } {
				lines << 'LINUX MASKWAIT MISMATCH: signal=' + signal.str() + ' wait=' + kind.str() + ' mode=' + mode.str() + ' stage=' + stage.str()
			}
		}
	} } } }
	lines << 'LINUX MASKWAIT SUMMARY: checks=1256 failures=' + if baseline { '160' } else { '0' }
	lines << 'LINUX MASKWAIT: ' + if baseline { 'FAIL' } else { 'PASS' }
	return lines
}
fn serial(text string, baseline bool, linux bool) ! {
	for bad in ['LINUX MASKWAIT FAIL:', 'REFERENCE FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', 'BUG:'] {
		require(!text.contains(bad), 'Failure marker: ' + bad)!
	}
	if linux { require(text.contains('Linux version '), 'Linux boot missing')! }
	mut wanted := map[string]int{}
	for line in expected(baseline) { wanted[line]++ }
	mut actual := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX MASKWAIT') {
			require(line in wanted, 'Unexpected record: ' + line)!
			actual[line]++
		}
	}
	require(actual == wanted, 'Missing, repeated or altered records')!
}
fn controls() ! {
	mut negatives := 0
	for baseline in [false, true] {
		good := 'Linux version control\n' + expected(baseline).join('\n') + '\n'
		serial(good, baseline, true)!
		for line in expected(baseline) {
			for bad in [good.replace(line + '\n', ''), good + line + '\n'] {
				serial(bad, baseline, true) or { negatives++; continue }
				return error('Missing/duplicate negative accepted')
			}
		}
		for bad in [good.replace('checks=1256', 'checks=1255'), good + 'Kernel panic injected\n', good + 'LINUX MASKWAIT UNKNOWN\n'] {
			serial(bad, baseline, true) or { negatives++; continue }
			return error('Alteration negative accepted')
		}
	}
	println('Masked-wait evidence parser: PASS (2 positive, ' + negatives.str() + ' negative)')
}
fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root + '/manifest.json')!)!
	mut actual := map[string]string{}
	for path in os.walk_ext(root, '') {
		if !os.is_file(path) || path == root + '/manifest.json' { continue }
		name := path[root.len + 1..]
		require(!os.is_link(path), 'Unexpected symlink: ' + name)!
		actual[name] = digest(path)!
	}
	require(actual == manifest, 'Bundle file inventory or SHA-256 mismatch')!
	before := os.read_file(root + '/build-base-x86/blob.c')!
	after := os.read_file(root + '/build-fixed-x86/blob.c')!
	old := 't->masked_signals = previous_mask | sigaction.sa_mask;'
	new := 't->masked_signals |= sigaction.sa_mask;'
	require(before.count(old) == 1 && before.replace(old, new) == after,
		'Generated C differs beyond the single scalar assignment')!
	for name in ['reference-arm', 'reference-x86', 'native-arm', 'native-x86', 'baseline-x86'] {
		serial(os.read_file(root + '/' + name + '/serial.log')!, name == 'baseline-x86', name.starts_with('reference'))!
	}
	// Bind identical native probe bytes across the Vinix and Linux boots.
	for pair in [['arm', 'build-arm'], ['x86', 'build-fixed-x86']] {
		suffix := pair[0]
		probe := digest(root + '/compile-' + suffix + '-r1/probe')!
		require(probe == digest(root + '/reference-' + suffix + '/probe')!
			&& probe == digest(root + '/native-' + suffix + '/rootfs/sbin/init')!, 'Probe differs across kernels')!
		require(digest(root + '/' + pair[1] + '/kernel/bin/vinix')!
			== digest(root + '/native-' + suffix + '/kernel/bin/vinix')!, 'Different tested kernel')!
		if suffix == 'x86' {
			require(probe == digest(root + '/baseline-x86/rootfs/sbin/init')!, 'Different baseline probe')!
			require(digest(root + '/build-base-x86/kernel/bin/vinix')!
				== digest(root + '/baseline-x86/kernel/bin/vinix')!, 'Different baseline kernel')!
		}
	}
	for arch in ['arm', 'x86'] {
		receipt := json2.decode[json2.Any](os.read_file(root + '/maintained-' + arch + '/receipt.json')!)!
		kernel := digest(root + '/build-' + if arch == 'arm' { 'arm' } else { 'fixed-x86' } + '/kernel/bin/vinix')!
		require(receipt.as_map()['kernel_sha256']!.str() == kernel, 'Maintained kernel differs')!
		mut names := []string{}
		for result in receipt.as_map()['results']!.as_array() {
			item := result.as_map()
			require(item['exit_code']!.int() == 0, 'Maintained case failed')!
			name := item['name']!.str()
			require(name !in names, 'Repeated maintained case')!
			names << name
			require(item['init_sha256']!.str() == digest(root + '/maintained-' + arch + '/' + name + '/init')!
				&& item['iso_sha256']!.str() == digest(root + '/maintained-' + arch + '/' + name + '/test.iso')!, 'Maintained artifact differs')!
			log := os.read_file(root + '/maintained-' + arch + '/' + name + '/serial.log')!
			require(log.contains('LINUX ' + name.to_upper() + ': PASS') && !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION'), 'Maintained PASS missing or kernel failure')!
			if name == 'maskwait' { serial(log, false, false)! }
		}
		names.sort()
		require(names == ['altstackrestore', 'jit', 'maskwait', 'resethand', 'runtime', 'seccomp', 'sigmaskcopy', 'sigwaitorder'], 'Incomplete maintained suite')!
	}
	println('Masked-wait complete bundle: PASS (' + manifest.len.str() + ' files)')
}
fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { controls() or { panic(err) }; return }
	if os.args.len == 5 && os.args[1] == 'serial' {
		serial(os.read_file(os.args[4])!, os.args[2] == 'baseline', os.args[3] == 'linux') or { panic(err) }
		println('Masked-wait serial: PASS'); return
	}
	if os.args.len != 3 || os.args[1] != 'check' { eprintln('Usage: maskwait-evidence self-test | serial baseline|fixed linux|vinix LOG | check BUNDLE'); exit(2) }
	check(os.real_path(os.args[2])) or { panic(err) }
}
