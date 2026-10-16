// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import hosttest

const scope = 'Pinned exact10 scheduler/MM declaration boundary, original kobject API/record/callback types, atomic failure and genuine unresolved MM links. No MM runtime or kobject lifecycle implementation is supplied by this test.'
const expected_output = '91207764611d8eed39f218781bc0927c1dc3599c39d4a0181e96ee4db239c8dd'
const sentinel = 'existing output must survive a rejected generation\n'

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn rejected(original string, output string, label string, mut controls []json2.Any) ! {
	before := if os.exists(output) && os.is_file(output) { hosttest.sha(output)! } else { '' }
	if _ := hosttest.generate_sched_mm(original, output) {
		return error('Accepted unsupported generation: ' + label)
	} else {
		if before != '' {
			require(hosttest.sha(output)! == before, 'Rejected generation changed output: ' + label)!
		} else {
			require(!os.is_file(output), 'Rejected generation created output: ' + label)!
		}
		controls << json2.Any({
			'case':             json2.Any(label)
			'error':            err.msg()
			'unchanged_output': true
		})
	}
}

fn generation_capture(argv []string, _log string, _timeout int, environment map[string]string) !hosttest.Result {
	output := argv[argv.index('-o') + 1]
	mut env := environment.clone()
	for key, directory in {
		'VCACHE':  'vcache'
		'V3CACHE': 'v3cache'
		'VTMP':    'vtmp'
		'TMPDIR':  'tmp'
	} {
		env[key] = os.dir(output) + '/' + directory
		os.mkdir_all(env[key])!
	}
	mut recorded := map[string]string{}
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE', 'VCACHE', 'V3CACHE', 'VTMP', 'TMPDIR'] {
		recorded[key] = env[key] or { '<unset>' }
	}
	hosttest.write_json(output + '.generation-environment.json', hosttest.string_map(recorded))!
	return hosttest.command(argv, output + '.generation.log', 180, env)
}

fn flags(work string, linux string, standard string) ![]string {
	root := hosttest.root()
	mut argv := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	argv << ['--target=x86_64-unknown-none', '-std=' + standard, '-O2', '-g', '-ffreestanding',
		'-fno-builtin', '-fno-stack-protector', '-fstack-usage', '-nostdinc', '-fno-pic', '-fno-pie',
		'-fwrapv', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-Wno-sign-compare', '-Wno-typedef-redefinition', '-D__KERNEL__', '-DVINIX_LINUXKPI', '-include',
		'linux/kconfig.h', '-include', linux + '/include/linux/compiler_types.h', '-isystem',
		root + '/kernel/freestnd-c-hdrs']
	for path in [work + '/include', root + '/tests/linuxkpi/schedmmfixture',
		root + '/kernel/linuxkpi/include', root + '/kernel/c', linux + '/include',
		linux + '/include/uapi', linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
		argv << ['-I', path]
	}
	return argv
}

fn run(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	hosttest.verify_upstream(linux, hosttest.upstream_pin()!)!
	work := hosttest.work_dir(keep, 'vinix-sched-mm-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	original := linux + '/include/linux/sched/mm.h'
	mut inputs := [@FILE, os.executable(), original, root + '/tests/linuxkpi/generate_sched_mm.v',
		root + '/tests/linuxkpi/schedmmfixture/core.v',
		root + '/tests/linuxkpi/schedmmfixture/contract.h',
		root + '/kernel/linuxkpi/include/generated/autoconf.h']
	inputs << os.walk_ext(root + '/tests/linuxkpi/hosttest', '.v')
	for executable in [hosttest.tool('llvm-nm'), hosttest.tool('ld.lld'),
		hosttest.shell_split(hosttest.env_default('CC', 'clang'))![0]] {
		inputs << os.find_abs_path_of_executable(executable)!
	}
	before := hosttest.hashes(inputs)!
	data := os.read_file(original)!
	pure := hosttest.sched_mm_declarations(data)!
	require(hosttest.text_sha(pure.header) == expected_output && pure.signatures.len == 10
		&& pure.original_definition_sha256.len == 10 && pure.unchanged_segment_sha256.len == 11,
		'Changed pinned declaration transformation')!
	mut generated := []json2.Any{}
	for iteration in 0 .. 3 {
		path := work + '/repeat' + iteration.str() + '/linux/sched/mm.h'
		provenance := hosttest.generate_sched_mm(original, path)!
		require(hosttest.sha(path)! == expected_output, 'Nondeterministic header generation')!
		state := hosttest.bounds_file_state(path)!
		hosttest.generate_sched_mm(original, path)!
		require(hosttest.bounds_file_state(path)! == state, 'Unchanged output was republished')!
		generated << json2.Any(provenance)
	}
	mut controls := []json2.Any{}
	for label, mutation in {
		'one-byte-drift':                data + '\n'
		'changed-original-prototype':    data.replace('in_vfork(struct task_struct *tsk)', 'in_vfork(const struct task_struct *tsk)')
		'duplicate-definition':          data + '\nstatic inline bool in_vfork(struct task_struct *tsk) { return false; }\n'
		'changed-original-body':         data.replace('ret = tsk->vfork_done &&', 'ret = false &&')
		'changed-configured-off-branch': data.replace('return NULL;', 'return (void *)1;')
	} {
		input := work + '/controls/' + label + '.h'
		os.mkdir_all(os.dir(input))!
		os.write_file(input, mutation)!
		for exists in [false, true] {
			target := input + if exists { '.existing.h' } else { '.absent.h' }
			if exists { os.write_file(target, sentinel)! }
			rejected(input, target, label + if exists { '-existing' } else { '-absent' }, mut controls)!
		}
	}
	private_original := work + '/private-linux/include/linux/sched/mm.h'
	os.mkdir_all(os.dir(private_original))!
	os.write_file(private_original, data)!
	for label, target in {
		'same-input':             private_original
		'inside-original-import': work + '/private-linux/generated/sched-mm.h'
	} {
		rejected(private_original, target, label, mut controls)!
	}
	alias := work + '/controls/original-symlink.h'
	os.symlink(private_original, alias)!
	rejected(private_original, alias, 'symlink-to-original', mut controls)!
	hardlink := work + '/controls/original-hardlink.h'
	os.link(private_original, hardlink)!
	rejected(private_original, hardlink, 'hardlink-to-original', mut controls)!
	parent_alias := work + '/controls/import-directory'
	os.symlink(work + '/private-linux', parent_alias)!
	rejected(private_original, parent_alias + '/new/header.h', 'symlink-parent-inside-import', mut controls)!
	directory := work + '/directory-output'
	os.mkdir_all(directory)!
	os.write_file(directory + '/sentinel', sentinel)!
	rejected(private_original, directory, 'directory-output', mut controls)!
	require(os.read_file(directory + '/sentinel')! == sentinel, 'Directory failure damaged existing data')!
	target := work + '/controls/missing-input-existing.h'
	os.write_file(target, sentinel)!
	rejected(work + '/missing-input', target, 'missing-input-existing-output', mut controls)!
	blocked_parent := work + '/controls/blocked-parent'
	os.write_file(blocked_parent, sentinel)!
	rejected(private_original, blocked_parent + '/output.h', 'publication-parent-is-file', mut controls)!
	require(os.read_file(blocked_parent)! == sentinel, 'Publication failure changed parent')!
	require(os.read_file(private_original)! == data && os.read_file(hardlink)! == data,
		'Negative control changed original input bytes')!
	// Replace an old output atomically only on a successful validated generation.
	stale := work + '/stale-header.h'
	os.write_file(stale, sentinel)!
	hosttest.generate_sched_mm(original, stale)!
	require(hosttest.sha(stale)! == expected_output, 'Successful replacement retained stale bytes')!
	hosttest.audit_headers_from_source(work + '/include', linux)!
	compiler := hosttest.env_default('CC', 'clang')
	compiler_parts := hosttest.shell_split(compiler)!
	bounds := work + '/include/generated/bounds.h'
	native_flags := flags(work, linux, 'gnu11')!
	hosttest.generate_bounds(linux, os.dir(linux) + '/linux-6.6.157.tar.xz', bounds,
		bounds + '.d', bounds + '.json', compiler, native_flags[compiler_parts.len..])!
	actual := work + '/schedmmfixture-actual.c'
	hosttest.generate_module_with_capture(root + '/tests/linuxkpi/schedmmfixture', actual,
		'amd64', ['nofloat'], generation_capture)!
	bodies := hosttest.c_bodies(os.read_file(actual)!).filter(it.all_before('\n').contains(' schedmmfixture__requires_runtime('))
	require(bodies.len == 1, 'Missing actual generated MM caller')!
	for forbidden in ['memdup(', 'new_array', 'new_map', 'v_malloc(', 'string__substr(',
		'box_to_interface', '__eq('] {
		require(!bodies[0].contains(forbidden), 'Hidden MM caller allocation/equality: ' + forbidden)!
	}
	selected := work + '/schedmmfixture-selected.c'
	os.write_file(selected, '#include "contract.h"\n' + bodies[0] + '\n')!
	mut objects := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		object := work + '/' + standard + '.o'
		argv := [...flags(work, linux, standard)!, '-MD', '-MF', object + '.d', '-MT', object,
			'-c', selected, '-o', object]
		hosttest.command(argv, object + '.compile.log', 90, os.environ())!
		dependencies := hosttest.hashes(hosttest.dependency_paths(os.read_file(object + '.d')!, object)!)!
		imports := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', object],
			object + '.imports.log', 30, os.environ())!.stdout
		mut names := imports.split_into_lines().filter(it.fields().len > 0).map(it.fields().last())
		names.sort()
		mut expected := pure.signatures.keys()
		expected.sort()
		require(names == expected, 'MM boundary changed genuine unresolved imports: ' + imports)!
		link := hosttest.capture([hosttest.tool('ld.lld'), '-m', 'elf_x86_64', '--nostdlib', '-e',
			'schedmmfixture__requires_runtime', object, '-o', object + '.elf'],
			object + '.rejected-link.log', 30, os.environ())!
		require(link.code != 0 && !os.exists(object + '.elf'), 'Unsupported MM caller linked')!
		for name in expected {
			require(link.stderr.contains('undefined symbol: ' + name), 'Missing unresolved MM symbol ' + name)!
		}
		stack := os.read_file(object[..object.len - 2] + '.su')!
		require(stack != '' && stack.split_into_lines().all(it == '' || it.ends_with('\tstatic')), 'Unbounded native caller stack')!
		for key, value in {
			'CONFIG_BASE_FULL':  0
			'CONFIG_BASE_SMALL': 1
		} {
			invalid := work + '/' + key + '.invalid.h'
			os.write_file(invalid, '#undef ' + key + '\n#define ' + key + ' ' + value.str() + '\n')!
			failed := hosttest.capture([...flags(work, linux, standard)!, '-include', invalid,
				'-fsyntax-only', selected],
				object + '.' + key + '.rejected-config.log', 60, os.environ())!
			require(failed.code != 0 && failed.stderr.contains('native profile requires BASE_FULL=1 and BASE_SMALL=0'), 'Accepted incoherent native profile')!
		}
		objects << json2.Any({
			'standard':                 json2.Any(standard)
			'object':                   object
			'argv':                     hosttest.strings(argv)
			'dependency_sha256':        hosttest.string_map(dependencies)
			'exact_unresolved_imports': hosttest.strings(names)
			'negative_link_exit':       link.code
		})
	}
	require(before == hosttest.hashes(before.keys())!, 'Focused generator source/tool inputs changed')!
	hosttest.verify_upstream(linux, hosttest.upstream_pin()!)!
	hosttest.write_json(work + '/result.json', {
		'status':                                 json2.Any('PASS original header declaration preservation, atomic rejection and genuine unresolved MM gates')
		'scope':                                  scope
		'generated_header_sha256':                expected_output
		'deterministic_repetitions':              3
		'negative_generation_controls':           controls
		'generations':                            generated
		'actual_generated_MM_caller_body_sha256': hosttest.text_sha(bodies[0])
		'objects':                                objects
		'source_sha256':                          hosttest.string_map(before)
		'artifact_sha256':                        hosttest.string_map(hosttest.hashes(os.walk_ext(work, ''))!)
	})!
	println('PASS scheduler/MM declaration boundary: ten exact externs; ' + controls.len.str() +
		' unchanged-output rejection controls; GNU99/GNU11 original records and ten unresolved MM imports')
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: sched_mm.v [--keep-dir NEW]', scope) or {
		eprintln(err)
		exit(2)
	}
	run(keep) or {
		eprintln(err)
		exit(1)
	}
}
