// SPDX-License-Identifier: GPL-2.0-or-later
// Audit the complete candidate execution bundle. Historical failed kernels
// remain in their original selectempty bundle and are not replayed here.
module main

import crypto.sha256
import execowncheck
import json2
import os
import selectcheck

fn require(good bool, reason string) ! {
	if !good { return error(reason) }
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn body(source string, name string) !string {
	mut offset := 0
	mut start := -1
	for line in source.split_into_lines() {
		if !line.starts_with('\t') && line.contains(' ' + name + '(') && line.ends_with(' {') {
			require(start == -1, 'Repeated function definition')!
			start = offset
		}
		offset += line.len + 1
		if start >= 0 && line == '}' {
			return source[start..if offset <= source.len { offset } else { source.len }]
		}
	}
	return error('Missing function: ' + name)
}

fn generated(source string, arch string) ! {
	require(arch in ['aarch64', 'x86_64'], 'Unsupported architecture')!
	importer := body(source, 'userland__exec_strings_from_user')!
	require(importer.count('string__clone(text)') == 1, 'Imported string is not explicitly cloned once')!
	clone_at := importer.index(' = string__clone(text);') or { return error('Missing compact clone assignment') }
	line_start := importer[..clone_at].last_index('\n') or { return error('Missing clone declaration') }
	declaration := importer[line_start + 1..clone_at].trim_space()
	require(declaration.starts_with('string '), 'Unexpected compact clone declaration')!
	variable := declaration['string '.len..]
	require(variable.len > 0 && variable.bytes().all(it.is_alnum() || it == `_`), 'Invalid clone local')!
	push := 'array_push(&strings, &' + variable + ');'
	push_at := importer.index(push) or { return error('Compact clone is not transferred to the vector') }
	free_at := importer.last_index('string__free(&text);') or { return error('Import buffer is not released') }
	require(clone_at < push_at && push_at < free_at, 'Import ownership order changed')!
	require(importer.count('string__free(&text);') == 3, 'Import cleanup paths changed')!
	loader := body(source, 'userland__load_program_image')!
	require(loader.contains('final_argv.flags |= 1;'), 'Missing script capacity ownership')!
	for name in ['real_path', 'arg'] {
		require(loader.contains('string__clone(' + name + ')')
			|| loader.contains('string__clone(*' + name + ')'), 'Missing owned script argument: ' + name)!
	}
	if arch == 'aarch64' {
		for token in ['string__clone(guest_root)', 'string__clone(environment_entry)'] {
			require(loader.contains(token), 'Missing owned translated environment: ' + token)!
		}
		native := body(source, 'userland__load_native_program_image')!
		require(native.contains('string__clone(entry)'), 'Missing owned filtered native environment')!
		for name in ['library_text_result', 'drivers_text_result', 'preload_text_result'] {
			require(!loader.contains('string__free(&' + name + ')'), 'Premature translated string release')!
		}
	}
}

fn pin(inputs map[string]string, suffix string, expected string) ! {
	mut found := 0
	for name, value in inputs {
		if name.ends_with(suffix) {
			require(value == expected, 'Different pinned input: ' + name)!
			found++
		}
	}
	require(found == 1, 'Missing/ambiguous pin: ' + suffix)!
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn session(state string, arch string, kernel string, probe string, name string) ! {
	receipt := object(state + '/receipt.json')!
	require(receipt['architecture']!.str() == arch && receipt['case']!.str() == name, 'Different session architecture/case')!
	require(receipt['passed']!.bool() && receipt['finished']!.bool()
		&& receipt['status']!.int() == 0, 'Session did not pass')!
	require(receipt['kernel_sha256']!.str() == kernel
		&& receipt['probe_sha256']!.str() == probe, 'Different session kernel/probe pins')!
	require(digest(state + '/kernel/bin/vinix')! == kernel && digest(state + '/init')! == probe
		&& digest(state + '/rootfs/sbin/init')! == probe, 'Different retained session kernel/probe')!
	require(receipt['serial_sha256']!.str() == digest(state + '/serial.log')!, 'Different session serial bytes')!
	inputs := json2.decode[map[string]string](json2.encode(receipt['inputs']!))!
	pin(inputs, '/bin/vinix', kernel)!
	mut probe_pins := 0
	for input_path, value in inputs {
		if input_path.ends_with('/probe') || input_path.ends_with('/init') {
			require(value == probe, 'Different session input probe')!
			probe_pins++
		}
	}
	require(probe_pins == 1, 'Missing/ambiguous session input probe')!
}

fn inventory(root string, relative string, mut files map[string]string) ! {
	path := if relative == '' { root } else { root + '/' + relative }
	require(!os.is_link(path), 'Unexpected artifact symlink: ' + relative)!
	if os.is_dir(path) {
		for name in os.ls(path)! {
			child := if relative == '' { name } else { relative + '/' + name }
			if child != 'manifest.json' { inventory(root, child, mut files)! }
		}
	} else {
		require(os.is_file(path), 'Unexpected artifact type: ' + relative)!
		files[relative] = digest(path)!
	}
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root + '/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	require(actual == manifest, 'Missing, extra or altered artifact')!
	for pair in [['arm', 'aarch64'], ['x86', 'x86_64']] {
		suffix, arch := pair[0], pair[1]
		build := root + '/build-' + suffix + '-r1'
		kernel := digest(build + '/kernel/bin/vinix')!
		require(os.read_file(build + '/build.log.status')!.trim_space() == '0', 'Kernel build failed')!
		build_inputs := json2.decode[map[string]string](os.read_file(build + '/inputs.json')!)!
		for path in ['kernel/userland/exec.v', 'kernel/userland/exec_args.v',
			'kernel/userland/userland.v', 'kernel/userland/userland_arm64.v', 'kernel/elf/elf.v'] {
			pin(build_inputs, '/' + path, digest(root + '/source/' + path)!)!
		}
		outputs := json2.decode[map[string]string](os.read_file(build + '/outputs.json')!)!
		pin(outputs, '/kernel/bin/vinix', kernel)!
		pin(outputs, '/blob.c', digest(build + '/blob.c')!)!
		generated(os.read_file(build + '/blob.c')!, arch)!
		compile := root + '/compile-' + suffix
		probe := digest(compile + '/probe')!
		compilation := object(compile + '/receipt.json')!
		require(compilation['architecture']!.str() == arch, 'Different compile architecture')!
		inputs := json2.decode[map[string]string](json2.encode(compilation['inputs']!))!
		for name in ['core.v', 'storage.v'] {
			pin(inputs, '/execownfixture/' + name, digest(root + '/source/tests/linux-compat/execownfixture/' + name)!)!
		}
		pin(inputs, '/execownreferenceinit/core.v', digest(root + '/source/tests/linux-compat/execownreferenceinit/core.v')!)!
		compiled := json2.decode[map[string]string](json2.encode(compilation['outputs']!))!
		pin(compiled, '/probe', probe)!
		pin(compiled, '/reference-init', digest(compile + '/reference-init')!)!
		native := root + '/native-' + suffix
		session(native, arch, kernel, probe, 'execown')!
		execowncheck.verify(os.read_file(native + '/serial.log')!, arch, false)!
		reference := root + '/reference-' + suffix
		execowncheck.verify(os.read_file(reference + '/serial.log')!, arch, true)!
		receipt := object(reference + '/receipt.json')!
		require(receipt['architecture']!.str() == arch && receipt['passed']!.bool()
			&& receipt['finished']!.bool() && receipt['status']!.int() == 0, 'Linux reference failed')!
		require(digest(reference + '/probe')! == probe
			&& digest(reference + '/init')! == digest(compile + '/reference-init')!, 'Different Linux probe/launcher')!
		artifacts := receipt['artifacts']!.as_map()
		for key, path in {'kernel': 'linux', 'probe': 'probe', 'wrapper_elf': 'init',
			'initramfs': 'initramfs.cpio', 'serial': 'serial.log'} {
			require(artifacts[key]!.str() == digest(reference + '/' + path)!, 'Different Linux artifact: ' + key)!
		}
		require(artifacts['wrapper_source']!.str()
			== digest(root + '/source/tests/linux-compat/execownreferenceinit/core.v')!, 'Different Linux wrapper source')!
		maintained := root + '/maintained-' + suffix
		regressions := object(maintained + '/receipt.json')!
		require(regressions['architecture']!.str() == arch
			&& regressions['kernel_sha256']!.str() == kernel, 'Different maintained kernel')!
		mut names := []string{}
		for result in regressions['results']!.as_array() {
			item := result.as_map()
			name := item['name']!.str()
			require(name !in names, 'Repeated maintained case')!
			names << name
			state := maintained + '/' + name
			init := digest(state + '/init')!
			require(item['exit_code']!.int() == 0 && item['init_sha256']!.str() == init
				&& item['iso_sha256']!.str() == digest(state + '/test.iso')!, 'Different/failed maintained artifacts')!
			session(state, arch, kernel, init, name)!
			log := os.read_file(state + '/serial.log')!
			require(log.contains('LINUX ' + name.to_upper() + ': PASS')
				&& !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
				&& !log.contains('LINUX ' + name.to_upper() + ' FAIL'), 'Maintained verdict missing/failed')!
			if name == 'selectempty' { selectcheck.verify(log, arch, false, false)! }
			if name == 'jit' {
				expected := if arch == 'aarch64' {
					'dd7b3b7c90f2166485c7572a3d106f33d83dc978172d59d0bdfa6e19bd11cb77'
				} else { 'e199f2782686969b2a8061c2db4f52af59546e7a93179e52ebe4a18d0c1e22f4' }
				require(init == expected, 'JIT probe differs from the retained failing ELF')!
				require(log.contains('LINUX JIT PASS: ordinary-user approval, read-only runtime and default W^X')
					&& log.contains('LINUX JIT PASS: administrator revocation rejects future requests'), 'Incomplete JIT policy checks')!
			}
		}
		names.sort()
		require(names == ['altstackrestore', 'jit', 'maskwait', 'resethand', 'runtime', 'seccomp',
			'selectempty', 'sigmaskcopy', 'sigwaitorder'], 'Missing maintained cases')!
	}
	println('Exec ownership evidence: PASS (' + manifest.len.str() + ' files; candidate functional/cleanup checks, Linux comparisons and 9/9 maintained cases per architecture)')
}

fn self_test() ! {
	execowncheck.self_test()!
	mut generated_negatives := 0
	for arch in ['aarch64', 'x86_64'] {
		good := 'Array userland__exec_strings_from_user(u64 vector, u64 budget) {\n'
			+ '\tstring__free(&text);\n\tstring__free(&text);\n'
			+ '\tstring owned = string__clone(text);\n\tarray_push(&strings, &owned);\n'
			+ '\tstring__free(&text);\n}\n'
			+ 'int userland__load_program_image(void) {\n\tfinal_argv.flags |= 1;\n'
			+ '\tstring__clone(*real_path);\n\tstring__clone(*arg);\n'
			+ if arch == 'aarch64' {
				'\tstring__clone(guest_root);\n\tstring__clone(environment_entry);\n}\n' +
				'int userland__load_native_program_image(void) {\n\tstring__clone(entry);\n}\n'
			} else { '}\n' }
		generated(good, arch)!
		mut variants := [good.replace('string__clone(text)', 'text'),
			good.replace('array_push(&strings, &owned);', 'array_push(&strings, &text);'),
			good.replace('string__free(&text);\n}', '}'),
			good.replace('string__clone(*real_path)', '*real_path'),
			good.replace('string__clone(*arg)', '*arg'),
			good.replace('final_argv.flags |= 1;', ''),
			good.replace('\tarray_push(&strings, &owned);\n\tstring__free(&text);',
				'\tstring__free(&text);\n\tarray_push(&strings, &owned);')]
		if arch == 'aarch64' {
			for token in ['string__clone(guest_root)', 'string__clone(environment_entry)', 'string__clone(entry)'] {
				variants << good.replace(token, '')
			}
			for name in ['library_text_result', 'drivers_text_result', 'preload_text_result'] {
				variants << good.replace('final_argv.flags |= 1;', 'final_argv.flags |= 1;\n\tstring__free(&' + name + ');')
			}
		}
		for bad in variants {
			generated(bad, arch) or { generated_negatives++; continue }
			return error('Invalid generated ownership accepted')
		}
	}
	println('Exec ownership generated-C controls: PASS (2 positive, ' + generated_negatives.str() + ' negative controls)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { self_test() or { panic(err) }; return }
	if os.args.len == 5 && os.args[1] == 'serial' {
		require(os.args[3] in ['native', 'reference'], 'Invalid serial context')!
		execowncheck.verify(os.read_file(os.args[4])!, os.args[2], os.args[3] == 'reference') or { panic(err) }
		println('Exec ownership serial: PASS'); return
	}
	if os.args.len == 4 && os.args[1] == 'generated' {
		generated(os.read_file(os.args[3])!, os.args[2]) or { panic(err) }
		println('Exec ownership generated C: PASS'); return
	}
	if os.args.len != 3 || os.args[1] != 'check' {
		eprintln('Usage: execown-evidence self-test | serial ARCH native|reference LOG | generated ARCH BLOB-C | check BUNDLE')
		exit(2)
	}
	check(os.real_path(os.args[2])) or { panic(err) }
}
