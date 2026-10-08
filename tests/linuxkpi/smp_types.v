// SPDX-License-Identifier: GPL-2.0-or-later
// Original CSD compiler ABI/initializers; no SMP runtime is supplied.
module main

import os
import json2
import hosttest
import smpfixture

fn require(passed bool, message string) ! {
	if !passed { return error(message) }
}

fn invoke(argv []string, log string, success bool, environment map[string]string) !hosttest.Result {
	result := hosttest.capture(argv, log, 180, environment)!
	if success && result.code != 0 { return error('Compiler/runtime failed; see ' + log) }
	return result
}

fn imports(obj string) !(string, []string) {
	nm := hosttest.env_default('LLVM_NM', hosttest.tool('llvm-nm'))
	result := hosttest.capture([nm, '--undefined-only', obj], '', -1, os.environ())!
	if result.code != 0 { return error('Object symbol inspection failed: ' + result.stderr) }
	mut names := []string{}
	for line in result.stdout.split_into_lines() {
		words := line.fields()
		if words.len >= 2 && words[words.len - 2] == 'U' && words.last() !in names {
			names << words.last()
		}
	}
	names.sort()
	return result.stdout, names
}

struct Profile {
	name  string
	body  string
	flags []string
}

fn run_profile(keep string) ! {
	work := hosttest.work_dir(keep, 'vinix-smp-types-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	root := hosttest.root()
	here := hosttest.upstream_here()
	pin := hosttest.upstream_pin()!
	linux := hosttest.resolve_path(hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(hosttest.upstream_default(), 'linux-' + pin['version']!.str())))!
	archive := os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	cc := hosttest.env_default('CC', 'clang')
	compiler := hosttest.shell_split(cc)!
	observed := [@FILE, os.join_path(root, 'tests/linuxkpi/smpfixture/core.v'),
		os.join_path(here, 'include/generated/autoconf.h'), os.join_path(here, 'include/linux/smp.h'),
		os.join_path(here, 'include/asm/percpu.h'), os.join_path(linux, 'include/linux/smp.h'),
		os.join_path(linux, 'include/linux/smp_types.h'), os.join_path(linux, 'include/linux/llist.h'),
		os.join_path(linux, 'arch/x86/include/asm/percpu.h')]
	mut guarded := observed.clone()
	guarded << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	initial := hosttest.hashes(guarded)!
	include := os.join_path(work, 'include')
	hosttest.audit_headers(include)!
	bounds := os.join_path(include, 'generated/bounds.h')
	base := smpfixture.flags(linux, include, 'x86_64-unknown-none', 'gnu11')
	raw := hosttest.generate_bounds(linux, archive, bounds, bounds + '.d', bounds + '.json', cc, base)!
	provenance := hosttest.decode_json(hosttest.bounds_metadata_json(raw))!
	reference := os.join_path(work, 'reference')
	prefix := 'linux-' + pin['version']!.str() + '/'
	members := hosttest.archive_ascii_members(archive, [prefix + 'arch/arm64/include/'],
		[prefix + 'scripts/Makefile.extrawarn', prefix + 'arch/x86/Kconfig'])!
	mut reference_hashes := map[string]string{}
	for name, bytes in members {
		relative := name[prefix.len..]
		path := os.join_path(reference, relative)
		os.mkdir_all(os.dir(path))!
		os.write_file_array(path, bytes)!
		reference_hashes[relative] = hosttest.file_digest(path)!
	}
	extrawarn := os.read_file(os.join_path(reference, 'scripts/Makefile.extrawarn'))!
	mut warning_found := false
	for line in extrawarn.split_into_lines() {
		if line.starts_with('KBUILD_CFLAGS') {
			words := line['KBUILD_CFLAGS'.len..].fields()
			if words.len >= 2 && words[0] == '+=' && words[1] == '-Wno-sign-compare' {
				warning_found = true
			}
		}
	}
	require(warning_found, 'Pinned Linux does not supply the proposed sign-compare policy')!
	declaration := smpfixture.macro(os.read_file(os.join_path(linux, 'arch/x86/include/asm/percpu.h'))!, 'DECLARE_EARLY_PER_CPU_READ_MOSTLY')!
	preamble := '#define CONFIG_HAVE_ARCH_WITHIN_STACK_FRAMES 1\n#ifndef DECLARE_EARLY_PER_CPU_READ_MOSTLY\n' + declaration + '#endif\n'
	full_header := '#include "' + os.join_path(linux, 'include/linux/smp.h') + '"\n'
	os.write_file(os.join_path(work, 'prerequisites.h'), preamble)!
	mut results := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for target in ['x86_64-unknown-none', 'aarch64-unknown-none'] {
			tag := standard + '-' + target
			current := smpfixture.flags(linux, include, target, standard)
			profiles := [Profile{'node', smpfixture.node, current}, if target.starts_with('x86') {
				Profile{'full-prerequisite', preamble + full_header + smpfixture.node + smpfixture.layout, [
					...current,
					'-Wno-sign-compare',
				]}
			} else {
				Profile{'generic-record-SMP-off', '#undef CONFIG_SMP\n' + full_header + smpfixture.node + smpfixture.layout, current}
			}]
			for profile in profiles {
				source := os.join_path(work, tag + '-' + profile.name + '.c')
				os.write_file(source, profile.body)!
				obj := source.all_before_last('.') + '.o'
				dep := source.all_before_last('.') + '.d'
				argv := [...compiler, ...profile.flags, '-MD', '-MF', dep, '-MQ', obj, '-c', source,
					'-o', obj]
				invoke(argv, source.all_before_last('.') + '.log', true, os.environ())!
				output, _ := imports(obj)!
				require(output.trim_space() == '', 'Cold type/initializer object unexpectedly imports runtime: ' + output)!
				inputs := hosttest.dependency_paths(os.read_file(dep)!, obj)!
				for original in ['include/linux/smp_types.h', 'include/linux/llist.h'] {
					require(hosttest.resolve_path(os.join_path(linux, original))! in inputs, 'Actual original dependency missing: ' + original)!
				}
				if profile.name != 'node' {
					require(hosttest.resolve_path(os.join_path(linux, 'include/linux/smp.h'))! in inputs, 'CSD definitions were not supplied by the original full header')!
				}
				results << json2.Any(map[string]json2.Any{
					'standard':        json2.Any(standard)
					'target':          target
					'profile':         profile.name
					'argv':            hosttest.strings(argv)
					'object_sha256':   hosttest.file_digest(obj)!
					'runtime_imports': output
					'input_sha256':    hosttest.string_map(hosttest.hashes(inputs)!)
				})
			}
		}
		baseline := os.join_path(work, standard + '-production-header.c')
		os.write_file(baseline, full_header + smpfixture.layout)!
		outcome := invoke([...compiler,
			...smpfixture.flags(linux, include, 'x86_64-unknown-none', standard), '-Wno-sign-compare',
			'-fsyntax-only', baseline], baseline.all_before_last('.') + '.log', false, os.environ())!
		results << json2.Any(map[string]json2.Any{
			'standard':    json2.Any(standard)
			'profile':     'actual-production-original-full-header'
			'exit_code':   outcome.code
			'diagnostics': outcome.stderr
		})
		ref_source := os.join_path(work, standard + '-runtime-references.c')
		os.write_file(ref_source, preamble + full_header + smpfixture.reference)!
		ref_obj := ref_source.all_before_last('.') + '.o'
		invoke([...compiler, ...smpfixture.flags(linux, include, 'x86_64-unknown-none', standard),
			'-Wno-sign-compare', '-c', ref_source, '-o', ref_obj], ref_source.all_before_last('.') + '.log', true, os.environ())!
		output, symbols := imports(ref_obj)!
		mut wanted := ['smp_call_function_single', 'smp_call_function_single_async',
			'smp_call_function_many', 'smp_call_function', 'on_each_cpu_cond_mask',
			'__smp_call_single_queue', '__cpu_online_mask', 'smp_ops']
		wanted.sort()
		require(symbols == wanted, 'Original unresolved runtime references changed: ' + output)!
		results << json2.Any(map[string]json2.Any{
			'standard':        json2.Any(standard)
			'profile':         'genuine-unresolved-runtime-references'
			'object_sha256':   hosttest.file_digest(ref_obj)!
			'runtime_imports': output
		})
		wrong := os.join_path(work, standard + '-wrong-callback.c')
		os.write_file(wrong, preamble + full_header + 'static void wrong(int argument) {(void)argument;}\ncall_single_data_t reject = CSD_INIT(wrong, NULL);\n')!
		rejected := invoke([...compiler,
			...smpfixture.flags(linux, include, 'x86_64-unknown-none', standard), '-Wno-sign-compare',
			'-fsyntax-only', wrong], wrong.all_before_last('.') + '.log', false, os.environ())!
		require(rejected.code != 0 && rejected.stderr.contains('incompatible function pointer'), 'Wrong callback type was not rejected by actual CSD_INIT')!
		host_source := os.join_path(work, standard + '-host.c')
		host_annotation := $if macos { '#undef __section\n#define __section(name)\n' } $else { '' }
		os.write_file(host_source, '#undef CONFIG_SMP\n' + host_annotation + full_header + smpfixture.node + smpfixture.layout + smpfixture.runtime)!
		host_obj := host_source.all_before_last('.') + '.o'
		host_target := $if macos {
			$if arm64 {
				'arm64-apple-macos'
			} $else {
				'x86_64-apple-macos'
			}
		} $else { 'x86_64-unknown-linux-gnu' }
		host_flags := smpfixture.flags(linux, include, host_target, standard)
		sanitizer := ['-O1', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
		invoke([...compiler, ...host_flags, ...sanitizer, '-c', host_source, '-o', host_obj], host_source.all_before_last('.') + '.log', true, os.environ())!
		driver := os.join_path(work, standard + '-driver.c')
		os.write_file(driver, smpfixture.driver)!
		executable := os.join_path(work, standard + '-runtime')
		invoke([...compiler, '-std=' + standard, '-Wall', '-Wextra', '-Werror', ...sanitizer, driver,
			host_obj, '-o', executable], os.join_path(work, standard + '-link.log'), true, os.environ())!
		mut environment := os.environ()
		environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
		environment['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		runtime := invoke([executable], os.join_path(work, standard + '-run.log'), true, environment)!
		require(runtime.stderr == '', 'Unexpected sanitizer diagnostic: ' + runtime.stderr)!
		results << json2.Any(map[string]json2.Any{
			'standard':                       json2.Any(standard)
			'profile':                        'host-original-initializers-SMP-off'
			'object_sha256':                  hosttest.file_digest(host_obj)!
			'output':                         runtime.stdout.trim_space()
			'host_only_placement_annotation': host_annotation
		})
		println(standard + ': ' + runtime.stdout.trim_space())
	}
	arm_include := os.join_path(work, 'arm-profile')
	os.mkdir_all(os.join_path(arm_include, 'generated'))!
	os.write_file(os.join_path(arm_include, 'generated/autoconf.h'), '#define CONFIG_ARM64 1\n#define CONFIG_64BIT 1\n#define CONFIG_SMP 1\n#define CONFIG_NR_CPUS 256\n#define CONFIG_MMU 1\n#define CONFIG_ARM64_4K_PAGES 1\n#define CONFIG_ARM64_PAGE_SHIFT 12\n#define CONFIG_PGTABLE_LEVELS 4\n#define CONFIG_THREAD_INFO_IN_TASK 1\n')!
	arm_source := os.join_path(work, 'arm-original-smp-closure.c')
	os.write_file(arm_source, full_header + smpfixture.layout)!
	argv := [...compiler, '-I', arm_include, '-I', os.join_path(reference, 'arch/arm64/include'),
		'-I', os.join_path(reference, 'arch/arm64/include/uapi'),
		...smpfixture.flags(linux, include, 'aarch64-unknown-none', 'gnu11'), '-fsyntax-only',
		arm_source]
	arm := invoke(argv, os.join_path(work, 'arm-original-smp-closure.log'), false, os.environ())!
	results << json2.Any(map[string]json2.Any{
		'profile':     json2.Any('exact-archived-ARM-SMP-architecture-closure')
		'argv':        hosttest.strings(argv)
		'exit_code':   arm.code
		'diagnostics': arm.stderr
		'scope':       'Diagnostic only; missing generated architecture/service dependencies remain unsupported.'
	})
	require(initial == hosttest.hashes(guarded)!, 'Observed production/test sources changed during isolated checks')!
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':                         json2.Any(scope)
		'source_sha256':                 hosttest.string_map(hosttest.hashes(observed)!)
		'bounds':                        provenance
		'exact_early_declaration_macro': declaration
		'reference_sha256':              hosttest.string_map(reference_hashes)
		'pinned_sign_compare_policy':    'scripts/Makefile.extrawarn: KBUILD_CFLAGS += -Wno-sign-compare'
		'results':                       results
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: smp_types.v [--keep-dir DIRECTORY]', scope) or {
		eprintln(err.msg())
		exit(2)
	}
	run_profile(keep) or {
		eprintln(err.msg())
		exit(1)
	}
}

const scope = "Test original Linux CSD compiler ABI without supplying an SMP runtime.

The production x86 profile's current include blockers are recorded separately
from a private, declaration-only prerequisite profile. ARM initializer tests
use the original CONFIG_SMP=n branch solely for the unconditional 64-bit CSD
records; exact archived ARM SMP architecture closure is probed separately.
No CSD structures, callback interfaces or runtime implementations are replaced.
"
