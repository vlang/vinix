// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import selectreadycheck
import selectcheck
import strings
import crypto.sha256
import json2

fn require(good bool, reason string) ! { if !good { return error(reason) } }

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

// V includes the source file's absolute-path hash in ignored-variable names.
// Separate worktrees change that identifier component without changing code.
fn canonical(source string) string {
	mut result := strings.new_builder(source.len)
	mut position := 0
	for position < source.len {
		if source[position] == `_` && position + 10 <= source.len && source[position..position + 10] == '__discard_' {
			result.write_string('__discard_')
			position += '__discard_'.len
			for position < source.len && source[position] >= `0` && source[position] <= `9` { position++ }
		} else {
			result.write_u8(source[position])
			position++
		}
	}
	return result.str()
}

fn scope(raw_before string, raw_after string) ! {
	before, after := canonical(raw_before), canonical(raw_after)
	old := body(before, 'file__do_select')!
	new := body(after, 'file__do_select')!
	require(old != new && before.replace(old, new) == after, 'Generated C changes outside do_select')!
	for token in ['file__ppoll(', '__malloc(', '__calloc(', 'memdup(', 'new_array', 'new_map', '__free(', '__str('] {
		require(old.count(token) == new.count(token), 'Call, allocation or release changed: ' + token)!
	}
	require(old.count('count++') == 1 && new.count('count++') == 3, 'Ready bits are not counted separately')!
	require(old.contains('bool hit = false;') && !new.contains('bool hit = false;'), 'Per-descriptor counter remains')!
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn pin(inputs map[string]string, suffix string, expected string) ! {
	mut count := 0
	for name, value in inputs {
		if name.ends_with(suffix) {
			require(value == expected, 'Different pinned input: ' + name)!
			count++
		}
	}
	require(count == 1, 'Missing or ambiguous input pin: ' + suffix)!
}

fn inventory(root string, relative string, mut found map[string]string) ! {
	path := if relative == '' { root } else { root + '/' + relative }
	require(!os.is_link(path), 'Unexpected artifact symlink: ' + relative)!
	if os.is_dir(path) {
		for name in os.ls(path)! {
			inventory(root, if relative == '' { name } else { relative + '/' + name }, mut found)!
		}
	} else {
		require(os.is_file(path), 'Artifact is not a regular file: ' + relative)!
		if relative != 'manifest.json' { found[relative] = digest(path)! }
	}
}

fn document(path string) !map[string]json2.Any {
	value := json2.decode[json2.Any](os.read_file(path)!)!
	require(value is map[string]json2.Any, 'Expected JSON object: ' + path)!
	return value.as_map()
}

fn completed(record map[string]json2.Any, arch string, label string) ! {
	require(record['architecture']!.str() == arch, 'Different session architecture: ' + label)!
	require(record['finished']!.bool() && record['passed']!.bool()
		&& record['status']!.int() == 0, 'Session did not complete successfully: ' + label)!
}

fn statuses(path string, names []string) ! {
	for name in names {
		require(os.read_file(path + '/' + name + '.log.status')!.trim_space() == '0',
			'Command failed or status missing: ' + path + '/' + name)!
	}
}

fn check_reference(root string, state string, probe string, launcher string, arch string) ! {
	receipt := document(state + '/receipt.json')!
	completed(receipt, arch, state)!
	artifacts := json2.decode[map[string]string](json2.encode(receipt['artifacts']!))!
	for name, path in {
		'probe': state + '/probe', 'wrapper_elf': state + '/init',
		'kernel': state + '/linux', 'initramfs': state + '/initramfs.cpio',
		'serial': state + '/serial.log',
		'wrapper_source': state + '/source/selectreadyreferenceinit/core.v',
		'controller_source': root + '/source/tests/linux-compat/selectready-reference.v'
	} {
		require(artifacts[name] == digest(path)!, 'Different reference artifact: ' + name)!
	}
	require(artifacts['probe'] == probe && artifacts['wrapper_elf'] == launcher,
		'Reference used a different compiled probe or launcher')!
	require(artifacts['wrapper_source'] == digest(root + '/source/tests/linux-compat/selectreadyreferenceinit/core.v')!,
		'Different reference launcher source')!
	command := json2.decode[[]string](os.read_file(state + '/command.json')!)!
	require(command == json2.decode[[]string](json2.encode(receipt['command']!))!, 'Different reference command')!
	inputs := json2.decode[map[string]string](os.read_file(state + '/inputs.json')!)!
	for name in ['probe', 'init', 'linux', 'initramfs.cpio'] { pin(inputs, '/' + os.base(state) + '/' + name, digest(state + '/' + name)!)! }
	pin(inputs, '/selectreadyreferenceinit/core.v', artifacts['wrapper_source'])!
	pin(inputs, '/tests/linux-compat/selectready-reference.v', artifacts['controller_source'])!
}

fn check_maintained(root string, suffix string, arch string, kernel string) ! {
	maintained := root + '/maintained-' + suffix
	receipt := document(maintained + '/receipt.json')!
	require(receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel
		&& digest(maintained + '/kernel/bin/vinix')! == kernel, 'Different maintained kernel or architecture')!
	mut names := []string{}
	for result in receipt['results']!.as_array() {
		item := result.as_map()
		name := item['name']!.str()
		require(name in ['selectempty', 'maskwait', 'resethand', 'sigmaskcopy', 'altstackrestore', 'sigwaitorder', 'seccomp', 'runtime']
			&& name !in names, 'Unexpected or repeated maintained case: ' + name)!
		names << name
		require(item['exit_code']!.int() == 0, 'Maintained case failed: ' + name)!
		require(item['init_sha256']!.str() == digest(maintained + '/' + name + '/init')!
			&& item['iso_sha256']!.str() == digest(maintained + '/' + name + '/test.iso')!, 'Different maintained artifacts: ' + name)!
		log := os.read_file(maintained + '/' + name + '/serial.log')!
		require(log.count('LINUX ' + name.to_upper() + ': PASS') == 1, 'Maintained verdict missing or repeated: ' + name)!
		for bad in ['KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', ' MISMATCH', ' FAIL:'] {
			require(!log.contains(bad), 'Maintained failure marker: ' + name + ': ' + bad)!
		}
		if name == 'selectempty' { selectcheck.verify(log, arch, false, false)! }
		pins := json2.decode[map[string]string](json2.encode(item['source_inputs']!))!
		files := if name == 'selectempty' { ['core.v', 'storage.v'] } else { ['core.v'] }
		require(pins.len == files.len, 'Unexpected maintained source inputs: ' + name)!
		for file in files {
			frozen := digest(maintained + '/sources/' + name + 'fixture/' + file)!
			pin(pins, '/' + name + 'fixture/' + file, frozen)!
			if file == 'core.v' { require(item['source_sha256']!.str() == frozen, 'Different maintained source: ' + name)! }
		}
	}
	names.sort()
	require(names == ['altstackrestore', 'maskwait', 'resethand', 'runtime', 'seccomp', 'selectempty', 'sigmaskcopy', 'sigwaitorder'], 'Missing maintained cases')!
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root + '/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	require(actual == manifest && manifest.len > 0, 'Missing, extra or altered artifact')!
	for pair in [['arm', 'aarch64'], ['x86', 'x86_64']] {
		suffix, arch := pair[0], pair[1]
		compiled := root + '/compile-' + suffix + '-r3'
		compile_record := document(compiled + '/receipt.json')!
		require(compile_record['architecture']!.str() == arch, 'Different compilation architecture')!
		inputs := json2.decode[map[string]string](json2.encode(compile_record['inputs']!))!
		outputs := json2.decode[map[string]string](json2.encode(compile_record['outputs']!))!
		probe := digest(compiled + '/probe')!
		launcher := digest(compiled + '/reference-init')!
		pin(outputs, '/compile-' + suffix + '-r3/probe', probe)!
		pin(outputs, '/compile-' + suffix + '-r3/reference-init', launcher)!
		for name in ['selectreadyfixture', 'selectreadyreferenceinit'] {
			pin(inputs, '/' + name + '/core.v', digest(root + '/source/tests/linux-compat/' + name + '/core.v')!)!
		}
		statuses(compiled, ['generate-serial', 'generate-fixture', 'generate-reference',
			'compile-serial', 'compile-fixture', 'compile-reference', 'link-probe', 'link-reference-init'])!
		mut kernels := map[string]string{}
		for profile in ['base', 'fixed'] {
			build := root + '/build-' + profile + '-' + suffix
			statuses(build, ['build'])!
			kernel := digest(build + '/kernel/bin/vinix')!
			kernels[profile] = kernel
			pins := json2.decode[map[string]string](os.read_file(build + '/outputs.json')!)!
			pin(pins, '/kernel/bin/vinix', kernel)!
			pin(pins, '/blob.c', digest(build + '/blob.c')!)!
			if profile == 'fixed' {
				build_inputs := json2.decode[map[string]string](os.read_file(build + '/inputs.json')!)!
				pin(build_inputs, '/kernel/file/pselect.v', digest(root + '/source/kernel/file/pselect.v')!)!
			}
		}
		require(kernels['base'] != kernels['fixed'], 'Baseline and candidate kernels are identical')!
		scope(os.read_file(root + '/build-base-' + suffix + '/blob.c')!,
			os.read_file(root + '/build-fixed-' + suffix + '/blob.c')!)!
		for kind in ['baseline', 'native', 'reference'] {
			state := root + '/' + kind + '-' + suffix + '-r1'
			selectreadycheck.verify(os.read_file(state + '/serial.log')!, arch, kind == 'baseline', kind == 'reference')!
			if kind == 'reference' {
				check_reference(root, state, probe, launcher, arch)!
			} else {
				receipt := document(state + '/receipt.json')!
				completed(receipt, arch, kind + '-' + suffix)!
				kernel := kernels[if kind == 'baseline' { 'base' } else { 'fixed' }]
				require(receipt['probe']!.str() == probe && digest(state + '/rootfs/sbin/init')! == probe,
					'Different probe across native boots')!
				require(receipt['kernel']!.str() == kernel && digest(state + '/kernel/bin/vinix')! == kernel,
					'Different tested native kernel')!
				require(receipt['serial']!.str() == digest(state + '/serial.log')!, 'Different native serial receipt')!
				boot_inputs := json2.decode[map[string]string](os.read_file(state + '/inputs.json')!)!
				pin(boot_inputs, '/compile-' + suffix + '-r3/probe', probe)!
				pin(boot_inputs, '/kernel/bin/vinix', kernel)!
			}
		}
		check_maintained(root, suffix, arch, kernels['fixed'])!
	}
	println('Select readiness evidence: PASS (' + manifest.len.str() + ' files; 8 maintained suites per architecture; regular-file failures retained)')
}

fn copy_tree(source string, destination string) ! {
	require(!os.is_link(source), 'Restore regular artifact: ' + source)!
	if os.is_dir(source) {
		os.mkdir_all(destination)!
		for name in os.ls(source)! { copy_tree(source + '/' + name, destination + '/' + name)! }
	} else if os.is_file(source) {
		os.mkdir_all(os.dir(destination))!
		os.link(source, destination)!
	}
}

fn pack(area string, repo string, baseline string, output string) ! {
	require(!os.exists(output) && !output.starts_with(area + '/'), 'Fresh external destination required')!
	os.mkdir_all(output)!
	for name in os.ls(area)! {
		if name in ['kernel-arm', 'kernel-x86'] { continue }
		copy_tree(area + '/' + name, output + '/' + name)!
	}
	for suffix in ['arm', 'x86'] { copy_tree(baseline + '/build-fixed-' + suffix, output + '/build-base-' + suffix)! }
	for name in ['kernel/file/pselect.v', 'tests/linux-compat/run.v', 'tests/linux-compat/maskwait-host.v',
		'tests/linux-compat/selectreadyfixture/core.v', 'tests/linux-compat/selectreadyreferenceinit/core.v',
		'tests/linux-compat/selectreadycheck/core.v', 'tests/linux-compat/selectready-reference.v',
		'tests/linux-compat/selectready-evidence.v'] {
		os.mkdir_all(os.dir(output + '/source/' + name))!
		os.cp(repo + '/' + name, output + '/source/' + name)!
	}
	mut manifest := map[string]string{}
	mut paths := os.walk_ext(output, ''); paths.sort()
	for path in paths { if os.is_file(path) { manifest[path[output.len + 1..]] = digest(path)! } }
	os.write_file(output + '/manifest.json', json2.encode(manifest, prettify: true) + '\n')!
	println('Published ' + manifest.len.str() + ' files; manifest SHA-256 ' + digest(output + '/manifest.json')!)
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' {
		selectreadycheck.self_test() or { panic(err) }; return
	}
	if os.args.len == 5 && os.args[1] == 'serial' {
		require(os.args[3] in ['baseline', 'native', 'reference'], 'Invalid serial mode') or { panic(err) }
		selectreadycheck.verify(os.read_file(os.args[4]) or { panic(err) }, os.args[2], os.args[3] == 'baseline', os.args[3] == 'reference') or { panic(err) }
		println('Select readiness serial: PASS'); return
	}
	if os.args.len == 4 && os.args[1] == 'scope' {
		scope(os.read_file(os.args[2]) or { panic(err) }, os.read_file(os.args[3]) or { panic(err) }) or { panic(err) }
		println('Select readiness generated-C scope: PASS'); return
	}
	if os.args.len == 6 && os.args[1] == 'pack' { pack(os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.args[5]) or { panic(err) }; return }
	if os.args.len == 3 && os.args[1] == 'check' { check(os.real_path(os.args[2])) or { panic(err) }; return }
	eprintln('Usage: selectready-evidence self-test | serial ARCH baseline|native|reference LOG | scope OLD-C NEW-C | pack STATE REPO BASELINE-BUNDLE FRESH-OUTPUT | check BUNDLE')
	exit(2)
}
