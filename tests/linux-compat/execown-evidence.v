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
	consumer := body(source, 'userland__exec_format_error')!
	require(consumer.contains('userland__ExecErrorScratch*')
		&& consumer.contains('vinix_stack_alloc(sizeof(userland__ExecErrorScratch))')
		&& consumer.contains('owned->value = err;')
		&& consumer.contains('IError__free(&owned->value);'), 'Error consumer must borrow a concrete stack wrapper')!
	for allocation in ['memdup(', 'malloc(', 'v_malloc(', 'calloc('] {
		require(!consumer.contains(allocation), 'Error consumer allocates a wrapper: ' + allocation)!
	}
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

fn generated_delta(before string, after string) ! {
	old := body(before, 'userland__exec_format_error')!
	current := body(after, 'userland__exec_format_error')!
	require(old.count('memdup(') == 2 && old.count('IError__free(owned);') == 1,
		'Original boxed error cleanup differs')!
	require(!current.contains('memdup(') && current.count('IError__free(&owned->value);') == 1,
		'Candidate error cleanup differs')!
	declaration := 'typedef struct userland__ExecErrorScratch userland__ExecErrorScratch;\n'
	definition := 'struct userland__ExecErrorScratch {\n\tIError value;\n};\n\n'
	require(!before.contains('userland__ExecErrorScratch') && after.count(declaration) == 2
		&& after.count(definition) == 1, 'Concrete scratch declarations differ')!
	require(before.replace(old, current) == after.replace(declaration, '').replace(definition, ''),
		'Generated C changed outside error cleanup and its concrete wrapper')!
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
		baseline := root + '/baseline-' + suffix
		original_build := root + '/original-build-' + suffix
		require(os.read_file(original_build + '/build.log.status')!.trim_space() == '0', 'Original build failed')!
		original_outputs := json2.decode[map[string]string](os.read_file(original_build + '/outputs.json')!)!
		pin(original_outputs, '/kernel/bin/vinix', digest(original_build + '/kernel/bin/vinix')!)!
		pin(original_outputs, '/blob.c', digest(original_build + '/blob.c')!)!
		generated_delta(os.read_file(original_build + '/blob.c')!, os.read_file(build + '/blob.c')!)!
		execowncheck.verify_retained(os.read_file(baseline + '/serial.log')!, arch)!
		original := object(baseline + '/receipt.json')!
		require(original['architecture']!.str() == arch && !original['passed']!.bool()
			&& original['finished']!.bool() && original['status']!.int() == 0,
			'Original retention result differs')!
		require(original['probe_sha256']!.str() == probe && digest(baseline + '/init')! == probe
			&& digest(baseline + '/rootfs/sbin/init')! == probe, 'Different original probe')!
		require(original['kernel_sha256']!.str() == digest(baseline + '/kernel/bin/vinix')!
			&& original['kernel_sha256']!.str() == digest(original_build + '/kernel/bin/vinix')!
			&& original['kernel_sha256']!.str() != kernel
			&& original['serial_sha256']!.str() == digest(baseline + '/serial.log')!, 'Different original artifacts')!
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
				&& item['iso_sha256']!.str() == digest(state + '/test.iso')!, 'Different/failed maintained artifacts: ' + arch + '/' + name)!
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
		registered := root + '/registered-' + suffix
		registration := object(registered + '/receipt.json')!
		require(registration['architecture']!.str() == arch && registration['kernel_sha256']!.str() == kernel
			&& digest(registered + '/kernel/bin/vinix')! == kernel, 'Different registered-runner kernel')!
		rows := registration['results']!.as_array()
		require(rows.len == 1, 'Registered runner must select only execown')!
		row := rows[0].as_map()
		require(row['name']!.str() == 'execown' && row['exit_code']!.int() == 0,
			'Registered execown case did not pass')!
		require(row['init_sha256']!.str() == digest(registered + '/execown/init')!
			&& row['iso_sha256']!.str() == digest(registered + '/execown/test.iso')!, 'Changed registered artifacts')!
		frozen_inputs := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
		require(frozen_inputs.len == 2, 'Registered execown must freeze both fixture sources')!
		for name in ['core.v', 'storage.v'] {
			expected := digest(root + '/source/tests/linux-compat/execownfixture/' + name)!
			pin(frozen_inputs, '/execownfixture/' + name, expected)!
			require(digest(registered + '/sources/execownfixture/' + name)! == expected, 'Different frozen execown source')!
		}
		execowncheck.verify(os.read_file(registered + '/execown/serial.log')!, arch, false)!
	}
	println('Exec ownership evidence: PASS (' + manifest.len.str() + ' files; original retention, candidate functional/cleanup checks, Linux comparisons, registered runner and 9/9 maintained cases per architecture)')
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
			+ (if arch == 'aarch64' {
				'\tstring__clone(guest_root);\n\tstring__clone(environment_entry);\n}\n' +
				'int userland__load_native_program_image(void) {\n\tstring__clone(entry);\n}\n'
			} else { '}\n' })
			+ 'int userland__exec_format_error(IError err) {\n'
			+ '\tuserland__ExecErrorScratch* owned = (userland__ExecErrorScratch*)vinix_stack_alloc(sizeof(userland__ExecErrorScratch));\n'
			+ '\towned->value = err;\n\tIError__free(&owned->value);\n}\n'
		generated(good, arch)!
		mut variants := [good.replace('string__clone(text)', 'text'),
			good.replace('array_push(&strings, &owned);', 'array_push(&strings, &text);'),
			good.replace('string__free(&text);\n}', '}'),
			good.replace('string__clone(*real_path)', '*real_path'),
			good.replace('string__clone(*arg)', '*arg'),
			good.replace('final_argv.flags |= 1;', ''),
			good.replace('\tarray_push(&strings, &owned);\n\tstring__free(&text);',
				'\tstring__free(&text);\n\tarray_push(&strings, &owned);'),
			good.replace('IError__free(&owned->value);', ''),
			good.replace('owned->value = err;', ''),
			good.replace('sizeof(userland__ExecErrorScratch)', 'sizeof(IError)')]
		for allocation in ['memdup(', 'malloc(', 'v_malloc(', 'calloc('] {
			variants << good.replace('owned->value = err;', 'owned->value = err;\n\t' + allocation + '0);')
		}
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
	old := 'int userland__exec_format_error(IError err) {\n\tmemdup(memdup(0));\n\tIError__free(owned);\n}\n'
	new := 'typedef struct userland__ExecErrorScratch userland__ExecErrorScratch;\n'.repeat(2)
		+ 'struct userland__ExecErrorScratch {\n\tIError value;\n};\n\n'
		+ 'int userland__exec_format_error(IError err) {\n\tIError__free(&owned->value);\n}\n'
	generated_delta(old, new)!
	mut scope_negatives := 0
	for bad in [new + 'void unrelated(void) {}\n', new.replace('IError value;', 'IError value;\n\tu64 extra;'),
		new.replace('IError__free(&owned->value);', 'memdup(0);\n\tIError__free(&owned->value);'),
		new.replace('IError__free(&owned->value);', ''),
		new.replace('typedef struct userland__ExecErrorScratch userland__ExecErrorScratch;\n', '')] {
		generated_delta(old, bad) or { scope_negatives++; continue }
		return error('Invalid generated-C scope accepted')
	}
	println('Exec error generated-C scope: PASS (1 positive, ' + scope_negatives.str() + ' negative controls)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { self_test() or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == 'retained' {
		execowncheck.verify_retained(os.read_file(os.args[3])!, os.args[2]) or { panic(err) }
		println('Exec original retention: reproduced'); return
	}
	if os.args.len == 4 && os.args[1] == 'delta' {
		generated_delta(os.read_file(os.args[2])!, os.read_file(os.args[3])!) or { panic(err) }
		println('Exec error generated-C scope: PASS'); return
	}
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
		eprintln('Usage: execown-evidence self-test | retained ARCH LOG | delta BEFORE-C AFTER-C | serial ARCH native|reference LOG | generated ARCH BLOB-C | check BUNDLE')
		exit(2)
	}
	check(os.real_path(os.args[2])) or { panic(err) }
}
