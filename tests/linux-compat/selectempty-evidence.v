// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import selectcheck

fn require(good bool, reason string) ! { if !good { return error(reason) } }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn body(source string, name string) !string {
	mut offset := 0
	mut start := -1
	for line in source.split_into_lines() {
		if !line.starts_with('\t') && line.contains(' ' + name + '(') && line.ends_with(' {') {
			require(start == -1, 'Repeated function definition')!
			start = offset
		}
		offset += line.len + 1
		if start >= 0 && line == '}' { return source[start..offset] }
	}
	return error('Missing function: ' + name)
}
fn scope(before string, after string) ! {
	old := body(before, 'file__do_select')!
	new := body(after, 'file__do_select')!
	require(old != new && before.replace(old, new) == after, 'Generated C changes outside do_select')!
	require(old.count('file__ppoll(') == 1 && new.count('file__ppoll(') == 2, 'Empty sleep does not use ppoll')!
	for token in ['__malloc(', '__calloc(', 'memdup(', 'new_array', 'new_map', '__free(', '__str('] {
		require(old.count(token) == new.count(token), 'Allocation or release operation changed: ' + token)!
	}
}
fn pin(inputs map[string]string, suffix string, expected string) ! {
	mut found := 0
	for name, value in inputs {
		if name.ends_with(suffix) { require(value == expected, 'Different pinned input: ' + name)!; found++ }
	}
	require(found == 1, 'Missing/ambiguous input pin: ' + suffix)!
}
fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root + '/manifest.json')!)!
	mut actual := map[string]string{}
	for path in os.walk_ext(root, '') {
		if path == root + '/manifest.json' || !os.is_file(path) { continue }
		require(!os.is_link(path), 'Unexpected symlink')!
		actual[path[root.len + 1..]] = digest(path)!
	}
	require(actual == manifest, 'Missing, extra or altered artifact')!
	for pair in [['arm', 'aarch64'], ['x86', 'x86_64']] {
		suffix, arch := pair[0], pair[1]
		probe := digest(root + '/compile-' + suffix + '/probe')!
		for kind in ['baseline', 'native', 'reference'] {
			state := root + '/' + kind + '-' + suffix
			selectcheck.verify(os.read_file(state + '/serial.log')!, arch, kind == 'baseline', kind == 'reference')!
			require(probe == digest(state + if kind == 'reference' { '/probe' } else { '/rootfs/sbin/init' })!, 'Different probe across boots')!
			if kind == 'reference' {
				receipt := json2.decode[json2.Any](os.read_file(state + '/receipt.json')!)!.as_map()
				require(receipt['passed']!.bool() && receipt['finished']!.bool() && receipt['status']!.int() == 0, 'Reference session failed')!
			}
		}
		inputs := json2.decode[json2.Any](os.read_file(root + '/compile-' + suffix + '/receipt.json')!)!.as_map()['inputs']!.as_map()
		for name in ['core.v', 'storage.v'] {
			mut found := 0
			for path, value in inputs {
				if path.ends_with('/selectemptyfixture/' + name) {
					require(value.str() == digest(root + '/source/tests/linux-compat/selectemptyfixture/' + name)!, 'Different compiled source')!; found++
				}
			}
			require(found == 1, 'Fixture source pin missing')!
		}
		for profile in ['base', 'fixed'] {
			build := root + '/build-' + profile + '-' + suffix
			require(os.read_file(build + '/build.log.status')!.trim_space() == '0', 'Build failed')!
			pins := json2.decode[map[string]string](os.read_file(build + '/inputs.json')!)!
			pin(pins, '/kernel/file/pselect.v', digest(root + if profile == 'base' { '/attempts/base-pselect.v' } else { '/source/kernel/file/pselect.v' })!)!
			boot := root + '/' + if profile == 'base' { 'baseline' } else { 'native' } + '-' + suffix
			require(digest(build + '/kernel/bin/vinix')! == digest(boot + '/kernel/bin/vinix')!, 'Different tested kernel')!
		}
		scope(os.read_file(root + '/build-base-' + suffix + '/blob.c')!, os.read_file(root + '/build-fixed-' + suffix + '/blob.c')!)!
		maintained := root + '/maintained-' + suffix
		receipt := json2.decode[json2.Any](os.read_file(maintained + '/receipt.json')!)!.as_map()
		require(receipt['kernel_sha256']!.str() == digest(root + '/build-fixed-' + suffix + '/kernel/bin/vinix')!, 'Different maintained kernel')!
		mut names := []string{}
		for result in receipt['results']!.as_array() {
			item := result.as_map()
			name := item['name']!.str()
			require(name !in names, 'Maintained case repeated')!
			names << name
			require(item['init_sha256']!.str() == digest(maintained + '/' + name + '/init')!
				&& item['iso_sha256']!.str() == digest(maintained + '/' + name + '/test.iso')!, 'Different maintained artifacts')!
			log := os.read_file(maintained + '/' + name + '/serial.log')!
			if name == 'jit' {
				require(item['exit_code']!.int() == 1 && log.contains('KERNEL PANIC') && !log.contains('LINUX JIT: PASS'), 'Expected JIT failure differs')!
				for profile in ['baseline', 'candidate'] {
					state := root + '/jit-' + profile + '-' + suffix
					control := json2.decode[json2.Any](os.read_file(state + '/receipt.json')!)!.as_map()
					build := root + '/build-' + if profile == 'baseline' { 'base' } else { 'fixed' } + '-' + suffix
					require(control['reproduced_expected_failure']!.bool() && control['jit_result']!.str() == 'kernel_panic', 'JIT control did not reproduce its failure')!
					require(control['kernel_sha256']!.str() == digest(build + '/kernel/bin/vinix')!
						&& control['probe_sha256']!.str() == digest(maintained + '/jit/init')!, 'Different JIT control inputs')!
					require(digest(state + '/kernel/bin/vinix')! == digest(build + '/kernel/bin/vinix')!
						&& digest(state + '/init')! == digest(maintained + '/jit/init')!, 'Different retained JIT control bytes')!
					panic_log := os.read_file(state + '/serial.log')!
					require(panic_log.contains('Panic info: Slab: double free') && !panic_log.contains('LINUX JIT: PASS'), 'JIT panic reason differs')!
				}
				continue
			}
			require(item['exit_code']!.int() == 0, 'Maintained case failed')!
			require(log.contains('LINUX ' + name.to_upper() + ': PASS') && !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION'), 'Maintained verdict missing')!
			if name == 'selectempty' { selectcheck.verify(log, arch, false, false)! }
		}
		names.sort()
		require(names == ['altstackrestore', 'jit', 'maskwait', 'resethand', 'runtime', 'seccomp', 'selectempty', 'sigmaskcopy', 'sigwaitorder'], 'Missing maintained cases')!
	}
	println('Empty-select evidence: PASS (' + manifest.len.str() + ' files; maintained 8/9 per architecture; existing JIT slab double-free retained)')
}
fn copy_tree(source string, destination string) ! {
	require(!os.is_link(source), 'Restore regular artifact first: ' + source)!
	if os.is_dir(source) {
		os.mkdir_all(destination)!
		for name in os.ls(source)! { copy_tree(source + '/' + name, destination + '/' + name)! }
	} else if os.is_file(source) {
		os.mkdir_all(os.dir(destination))!; os.link(source, destination)!
	}
}
fn pack(area string, repo string, output string) ! {
	require(!os.exists(output) && !output.starts_with(area + '/'), 'Fresh external output required')!
	os.mkdir_all(output)!
	selected := {
		'build-base-arm-r1': 'build-base-arm', 'build-base-x86-r1': 'build-base-x86',
		'build-fixed-arm': 'build-fixed-arm', 'build-fixed-x86': 'build-fixed-x86',
		'compile-arm-r4': 'compile-arm', 'compile-x86-r4': 'compile-x86',
		'reference-arm-r1': 'reference-arm', 'reference-x86-r1': 'reference-x86',
		'baseline-arm': 'baseline-arm', 'baseline-x86': 'baseline-x86',
		'native-arm': 'native-arm', 'native-x86': 'native-x86',
		'maintained-arm': 'maintained-arm', 'maintained-x86': 'maintained-x86',
		'jit-baseline-arm': 'jit-baseline-arm', 'jit-baseline-x86': 'jit-baseline-x86',
		'jit-candidate-arm': 'jit-candidate-arm', 'jit-candidate-x86': 'jit-candidate-x86'
	}
	for name in os.ls(area)! {
		if name in ['kernel-arm', 'kernel-x86'] { continue }
		copy_tree(area + '/' + name, output + '/' + if name in selected { selected[name] } else { 'attempts/' + name })!
	}
	for name in ['kernel/file/pselect.v', 'tests/linux-compat/run.v', 'tests/linux-compat/maskwait-host.v',
		'tests/linux-compat/selectemptyfixture/core.v', 'tests/linux-compat/selectemptyfixture/storage.v',
		'tests/linux-compat/selectemptyreferenceinit/core.v', 'tests/linux-compat/selectcheck/core.v',
		'tests/linux-compat/selectempty-reference.v', 'tests/linux-compat/selectempty-evidence.v',
		'tests/linux-compat/selectempty-jit-control.v'] {
		os.mkdir_all(os.dir(output + '/source/' + name))!; os.cp(repo + '/' + name, output + '/source/' + name)!
	}
	mut manifest := map[string]string{}
	mut paths := os.walk_ext(output, ''); paths.sort()
	for path in paths { if os.is_file(path) { manifest[path[output.len + 1..]] = digest(path)! } }
	os.write_file(output + '/manifest.json', json2.encode(manifest, prettify: true) + '\n')!
	println('Published ' + manifest.len.str() + ' files; manifest SHA-256 ' + digest(output + '/manifest.json')!)
}
fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { selectcheck.self_test() or { panic(err) }; return }
	if os.args.len == 5 && os.args[1] == 'serial' {
		selectcheck.verify(os.read_file(os.args[4])!, os.args[2], os.args[3] == 'baseline', os.args[3] == 'reference') or { panic(err) }
		println('Empty-select serial: PASS'); return
	}
	if os.args.len == 5 && os.args[1] == 'pack' { pack(os.real_path(os.args[2]), os.real_path(os.args[3]), os.args[4]) or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == 'scope' { scope(os.read_file(os.args[2])!, os.read_file(os.args[3])!) or { panic(err) }; println('Empty-select generated-C scope: PASS'); return }
	if os.args.len != 3 || os.args[1] != 'check' { eprintln('Usage: selectempty-evidence self-test | serial ARCH baseline|native|reference LOG | scope OLD-C NEW-C | pack STATE REPO FRESH-OUTPUT | check BUNDLE'); exit(2) }
	check(os.real_path(os.args[2])) or { panic(err) }
}
