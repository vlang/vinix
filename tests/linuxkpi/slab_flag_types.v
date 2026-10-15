// SPDX-License-Identifier: GPL-2.0-or-later
// Original slab flag type ownership, ABI and direct-header include ordering.
module main

import os
import json2
import hosttest
import smpfixture

const scope = 'Compile genuine production slab_flags_t type ownership and original disabled-KASAN declarations in strict native-target GNU99/GNU11 include orders. Historical wrong-owner controls must fail before slab.h. ARM probes cover only real generic scalar/cache declarations under an AArch64 compiler, not an ARM LinuxKPI runtime. No allocator, KASAN runtime or additional cache mode is implemented.'

const prior_slab_typedef = '#ifdef __CHECKER__\ntypedef unsigned int __attribute__((bitwise)) slab_flags_t;\n#else\ntypedef unsigned int slab_flags_t;\n#endif\n'

const type_assertions = '
_Static_assert(sizeof(slab_flags_t) == 4, "original slab flag width");
_Static_assert(__alignof__(slab_flags_t) == __alignof__(unsigned int), "original slab flag alignment");
_Static_assert(__builtin_types_compatible_p(slab_flags_t, unsigned int), "original unsigned-int identity");
_Static_assert((slab_flags_t)-1 > 0, "original slab flag signedness");
'

const cache_assertions = '
_Static_assert(__builtin_types_compatible_p(__typeof__(SLAB_HWCACHE_ALIGN), slab_flags_t),
    "cache flag preserves original type");
_Static_assert(SLAB_HWCACHE_ALIGN == 0x00002000U && SLAB_TYPESAFE_BY_RCU == 0x00080000U,
    "original flags do not gain new native semantics");
_Static_assert(__builtin_types_compatible_p(__typeof__(&kmem_cache_create),
    struct kmem_cache *(*)(const char *, unsigned int, unsigned int, slab_flags_t, void (*)(void *))),
    "cache allocation prototype remains unchanged");
'

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn flags(linux string, include string, target string, standard string) []string {
	// The AArch64 probes compile only architecture-independent type/prototype
	// headers from this explicitly x86-only compatibility profile. They do not
	// compile original x86 instruction helpers or claim an ARM LinuxKPI runtime.
	return smpfixture.flags(linux, include, target, standard)
}

fn compile_case(work string, tag string, source string, argv []string,
	expected bool, environment map[string]string) !json2.Any {
	obj := os.join_path(work, tag + '.o')
	dep := obj + '.d'
	preprocessed := obj + '.i'
	preprocess := [...argv, '-E', '-dD', '-MD', '-MF', dep, '-MQ', obj, source, '-o', preprocessed]
	hosttest.command(preprocess, obj + '.preprocess.log', 180, environment)!
	dependencies := hosttest.dependency_paths(os.read_file(dep)!, obj)!
	before := hosttest.hashes(dependencies)!
	command := [...argv, '-c', source, '-o', obj]
	result := hosttest.capture(command, obj + '.compile.log', 180, environment)!
	require((result.code == 0) == expected, 'Unexpected type-owner compile result: ' + obj +
		'; see ' + obj + '.compile.log')!
	if !expected {
		require(result.stderr.contains('slab_flags_t'), 'Wrong-owner control failed for an unrelated reason')!
	}
	mut imports := ''
	mut object_hash := ''
	if expected {
		imports = hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', obj],
			obj + '.imports.log', 30, environment)!.stdout
		require(imports.trim_space() == '', 'Cold type/prototype object imports a runtime: ' + imports)!
		object_hash = hosttest.sha(obj)!
	}
	require(before == hosttest.hashes(dependencies)!, 'Compiler dependency changed during validation')!
	return {
		'tag':                 json2.Any(tag)
		'compiler_argv':       hosttest.strings(command)
		'expected_success':    expected
		'exit':                result.code
		'source':              source
		'source_sha256':       hosttest.sha(source)!
		'object':              obj
		'object_sha256':       object_hash
		'preprocessed':        preprocessed
		'preprocessed_sha256': hosttest.sha(preprocessed)!
		'dependency_sha256':   hosttest.string_map(before)
		'compile_log':         obj + '.compile.log'
		'compile_log_sha256':  hosttest.sha(obj + '.compile.log')!
		'runtime_imports':     imports
	}
}

fn expanded_typedef(text string) !string {
	for line in text.split_into_lines() {
		if line.trim_space().starts_with('typedef ') && line.contains(' slab_flags_t;') {
			return line.fields().join(' ')
		}
	}
	return error('Preprocessing omitted the slab flag declaration')
}

fn sparse_annotation(work string, compiler []string, base []string, linux string,
	environment map[string]string) !json2.Any {
	os.mkdir_all(work)!
	mut results := []json2.Any{}
	mut values := []string{}
	for profile in ['production', 'original'] {
		source := os.join_path(work, 'sparse-' + profile + '.c')
		included := if profile == 'production' {
			'linux/types.h'
		} else {
			os.join_path(linux, 'include/linux/types.h')
		}
		os.write_file(source, '#include "' + included + '"\n')!
		output := os.join_path(work, 'sparse-' + profile + '.i')
		command := [...compiler, ...base, '-D__CHECKER__', '-E', source, '-o', output]
		hosttest.command(command, output + '.log', 180, environment)!
		value := expanded_typedef(os.read_file(output)!)!
		values << value
		results << json2.Any({
			'profile':          json2.Any(profile)
			'compiler_argv':    hosttest.strings(command)
			'expanded_typedef': value
			'output_sha256':    hosttest.sha(output)!
		})
	}
	require(values[0] == values[1]
		&& values[0] == 'typedef unsigned int __attribute__((bitwise)) slab_flags_t;',
		'Production Sparse annotation differs from the genuine original')!
	return {
		'scope':   json2.Any('Preprocessor-only comparison of the actual original Sparse annotation. No Sparse semantic analyzer or KASAN instrumentation is claimed.')
		'results': results
	}
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	here := hosttest.upstream_here()
	pin := hosttest.upstream_pin()!
	linux := hosttest.resolve_path(hosttest.env_default('LINUXKPI_SOURCE_DIR',
		os.join_path(hosttest.upstream_default(), 'linux-' + pin['version']!.str())))!
	archive := os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	hosttest.verify_upstream(linux, pin)!
	require(hosttest.sha(archive)! == pin['sha256']!.str(), 'Pinned archive differs')!
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	work := hosttest.work_dir(keep, 'vinix-slab-flags-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	types_path := os.join_path(here, 'include/linux/types.h')
	slab_path := os.join_path(here, 'include/linux/slab.h')
	types := os.read_file(types_path)!
	slab := os.read_file(slab_path)!
	member := 'linux-' + pin['version']!.str() + '/include/linux/types.h'
	original := hosttest.archive_members(archive, [member])![member]!
	require(original.bytestr() == os.read_file(os.join_path(linux, 'include/linux/types.h'))!,
		'Original type owner differs from the pinned archive')!
	mut typedef := ''
	for line in original.bytestr().split_into_lines() {
		if line.starts_with('typedef ') && line.ends_with(' slab_flags_t;') {
			require(typedef == '', 'Pinned original repeats the slab flag declaration')!
			typedef = line
		}
	}
	require(typedef == 'typedef unsigned int __bitwise slab_flags_t;', 'Pinned original alias changed')!
	require(types.count(typedef + '\n') == 1 && !slab.contains('typedef unsigned int'),
		'Production type owner or duplicate declaration regressed')!
	mut guarded := [@FILE, types_path, slab_path, os.join_path(linux, 'include/linux/types.h'),
		os.join_path(linux, 'include/uapi/linux/types.h'),
		os.join_path(linux, 'include/linux/kasan.h'), os.join_path(here, 'upstream.json'),
		os.join_path(root, 'tests/linuxkpi/smpfixture/core.v')]
	guarded << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	before := hosttest.hashes(guarded)!
	include := os.join_path(work, 'include')
	hosttest.audit_headers(include)!
	old_include := os.join_path(work, 'before/include')
	os.mkdir_all(os.join_path(old_include, 'linux'))!
	os.write_file(os.join_path(old_include, 'linux/types.h'), types.replace(typedef + '\n', ''))!
	os.write_file(os.join_path(old_include, 'linux/slab.h'), slab.replace('#include <linux/gfp_types.h>\n', '#include <linux/gfp_types.h>\n' + prior_slab_typedef))!
	orders := [
		['linux/types.h'],
		['linux/types.h', 'linux/slab.h', 'linux/kasan.h'],
		['linux/types.h', 'linux/kasan.h', 'linux/slab.h'],
		['linux/slab.h', 'linux/types.h', 'linux/kasan.h'],
		['linux/slab.h', 'linux/kasan.h', 'linux/types.h'],
		['linux/kasan.h', 'linux/types.h', 'linux/slab.h'],
		['linux/kasan.h', 'linux/slab.h', 'linux/types.h'],
		['uapi/linux/types.h', 'linux/kasan.h', 'linux/types.h', 'linux/slab.h'],
	]
	arm_orders := [
		['linux/types.h'],
		['linux/types.h', 'linux/slab.h'],
		['linux/slab.h', 'linux/types.h'],
		['uapi/linux/types.h', 'linux/types.h', 'linux/slab.h'],
	]
	mut results := []json2.Any{}
	mut sparse := []json2.Any{}
	environment := os.environ()
	for standard in ['gnu99', 'gnu11'] {
		for target in ['x86_64-unknown-none', 'aarch64-unknown-none'] {
			base := flags(linux, include, target, standard)
			selected_orders := if target.starts_with('x86') { orders } else { arm_orders }
			for index, headers in selected_orders {
				tag := standard + '-' + target + '-' + index.str()
				source := os.join_path(work, tag + '.c')
				mut text := ''
				for name in headers { text += '#include <' + name + '>\n' }
				text += type_assertions
				text += if target.starts_with('x86') {
					'_Static_assert(__x86_64__ == 1, "actual x86 target compiler");\n'
				} else {
					'_Static_assert(__aarch64__ == 1, "actual ARM target compiler");\n'
				}
				if 'linux/slab.h' in headers { text += cache_assertions }
				if 'linux/kasan.h' in headers {
					text += '_Static_assert(__builtin_types_compatible_p(__typeof__(kasan_never_merge()), slab_flags_t), "original disabled-KASAN return identity");\n'
				}
				os.write_file(source, text)!
				for old in [false, true] {
					name := tag + if old { '-wrong-owner' } else { '-production' }
					argv := [...compiler, ...(if old { ['-I', old_include] } else { []string{} }),
						...base]
					valid_old := 'linux/slab.h' in headers
						&& ('linux/kasan.h' !in headers
							|| headers.index('linux/slab.h') < headers.index('linux/kasan.h'))
					proof := compile_case(work, name, source, argv, !old || valid_old, environment)!
					dependencies := proof.as_map()['dependency_sha256']!.as_map()
					for header in ['include/uapi/linux/types.h', 'include/uapi/asm-generic/int-ll64.h'] {
						require(hosttest.resolve_path(os.join_path(linux, header))! in dependencies,
							'Type probe omitted an original dependency: ' + header)!
					}
					if 'linux/kasan.h' in headers {
						require(hosttest.resolve_path(os.join_path(linux, 'include/linux/kasan.h'))! in dependencies,
							'Type probe omitted the genuine original KASAN header')!
					}
					results << proof
				}
			}
			if target.starts_with('x86') {
				sparse << sparse_annotation(os.join_path(work, 'sparse-' + standard), compiler,
					base, linux, environment)!
			}
		}
		println(standard + ': original slab flag ownership/include orders and ARM scalar/cache declarations passed; historical wrong-owner controls verified')
	}
	require(before == hosttest.hashes(guarded)!, 'Type-owner source changed during validation')!
	hosttest.write_json(os.join_path(work, 'result.json'), {
		'scope':               json2.Any(scope)
		'source_sha256':       hosttest.string_map(before)
		'archive_sha256':      hosttest.sha(archive)!
		'original_typedef':    typedef
		'cases':               results
		'sparse_annotation':   sparse
		'wrong_owner_headers': hosttest.string_map(hosttest.hashes([
			os.join_path(old_include, 'linux/types.h'),
			os.join_path(old_include, 'linux/slab.h'),
		])!)
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: slab_flag_types.v [--keep-dir NEW]', scope) or {
		eprintln(err)
		exit(2)
	}
	run_profile(keep) or {
		eprintln(err)
		exit(1)
	}
}
