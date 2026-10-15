// SPDX-License-Identifier: GPL-2.0-or-later
// Genuine Linux declaration wrappers, incomplete FAM types and mirrored layout.
module main

import os
import json2
import hosttest
import smpfixture

const scope = 'Compile the six exact Linux 6.6.157 stddef wrappers through the unchanged UAPI owner. Strict GNU99/GNU11 x86-64 and actual AArch64 targets compare 32 declaration/layout facts and reject targeted mutations. ARM covers generic declarations only; LinuxKPI runtime remains x86-only. No memory mapping, device, allocator or GPU runtime is implemented.'

const prior_header = '/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_STDDEF_H
#define VINIX_LINUX_STDDEF_H
#include <stddef.h>
#endif
'

const layout = '
struct flex_tail { unsigned char prefix; union { unsigned long scalar; DECLARE_FLEX_ARRAY(unsigned long, values); }; };
union flex_union { unsigned long scalar; DECLARE_FLEX_ARRAY(unsigned long, values); };
struct flex_only { DECLARE_FLEX_ARRAY(unsigned char, bytes); };
union flex_dual { DECLARE_FLEX_ARRAY(unsigned char, bytes); DECLARE_FLEX_ARRAY(unsigned long, words); };
struct ordinary { unsigned char prefix; struct_group(group, unsigned char first; unsigned long last;); unsigned char suffix; };
struct packed { unsigned char prefix; struct_group_attr(group, __attribute__((packed)), unsigned char first; unsigned long last;); unsigned char suffix; };
struct aligned { unsigned char prefix; struct_group_attr(group, __attribute__((aligned(32))), unsigned char first; unsigned long last;); unsigned char suffix; };
struct tagged { unsigned char prefix; struct_group_tagged(reusable_group, group, unsigned char first; unsigned long last;); unsigned char suffix; };
_Static_assert(sizeof(unsigned long) == 8 && sizeof(void *) == 8, "LP64 profile");
_Static_assert(sizeof(struct flex_tail) == 16 && _Alignof(struct flex_tail) == 8 && offsetof(struct flex_tail, values) == 8, "wrapped FAM tail");
_Static_assert(sizeof_field(struct flex_tail, __empty_values) == 0 && offsetof(struct flex_tail, __empty_values) == 8, "empty named FAM anchor");
_Static_assert(sizeof(union flex_union) == 8 && _Alignof(union flex_union) == 8 && offsetof(union flex_union, values) == 0, "union FAM");
_Static_assert(sizeof(struct flex_only) == 0 && _Alignof(struct flex_only) == 1 && offsetof(struct flex_only, bytes) == 0, "standalone GNU FAM wrapper");
_Static_assert(sizeof(union flex_dual) == 0 && _Alignof(union flex_dual) == 8 && offsetof(union flex_dual, words) == 0, "distinct empty anchors");
_Static_assert(sizeof(struct ordinary) == 32 && _Alignof(struct ordinary) == 8 && offsetof(struct ordinary, group) == 8 && offsetof(struct ordinary, last) == 16 && offsetof(struct ordinary, suffix) == 24 && sizeof_field(struct ordinary, group) == 16, "ordinary mirrored group layout");
_Static_assert(offsetof(struct ordinary, first) == offsetof(struct ordinary, group.first) && offsetof(struct ordinary, last) == offsetof(struct ordinary, group.last), "anonymous and named member aliases");
_Static_assert(__builtin_types_compatible_p(__typeof__(((struct ordinary *)0)->last), __typeof__(((struct ordinary *)0)->group.last)), "anonymous and named member types");
_Static_assert(sizeof(struct packed) == 11 && _Alignof(struct packed) == 1 && offsetof(struct packed, group) == 1 && offsetof(struct packed, last) == 2 && offsetof(struct packed, suffix) == 10 && sizeof_field(struct packed, group) == 9 && _Alignof(__typeof__(((struct packed *)0)->group)) == 1, "packed attributes preserved on copies and union");
_Static_assert(sizeof(struct aligned) == 96 && _Alignof(struct aligned) == 32 && offsetof(struct aligned, group) == 32 && offsetof(struct aligned, last) == 40 && offsetof(struct aligned, suffix) == 64 && sizeof_field(struct aligned, group) == 32 && _Alignof(__typeof__(((struct aligned *)0)->group)) == 32, "alignment attributes preserved on copies and union");
_Static_assert(sizeof(struct reusable_group) == 16 && __builtin_types_compatible_p(__typeof__(((struct tagged *)0)->group), struct reusable_group), "reusable tag identifies named copy");
_Static_assert(offsetofend(struct ordinary, group) == 24 && sizeof_field(struct ordinary, group.last) == 8 && offsetofend(struct ordinary, group.last) == 24, "original nested field helpers");
const unsigned long stddef_layout_facts[] = {
 sizeof(struct flex_tail), _Alignof(struct flex_tail), offsetof(struct flex_tail, values), sizeof_field(struct flex_tail, __empty_values),
 sizeof(union flex_union), _Alignof(union flex_union), sizeof(struct flex_only), _Alignof(struct flex_only), sizeof(union flex_dual), _Alignof(union flex_dual),
 sizeof(struct ordinary), _Alignof(struct ordinary), offsetof(struct ordinary, group), offsetof(struct ordinary, last), offsetof(struct ordinary, suffix), sizeof_field(struct ordinary, group),
 sizeof(struct packed), _Alignof(struct packed), offsetof(struct packed, group), offsetof(struct packed, last), offsetof(struct packed, suffix), sizeof_field(struct packed, group),
 sizeof(struct aligned), _Alignof(struct aligned), offsetof(struct aligned, group), offsetof(struct aligned, last), offsetof(struct aligned, suffix), sizeof_field(struct aligned, group),
 sizeof(struct reusable_group), offsetofend(struct ordinary, group), sizeof_field(struct ordinary, group.last), offsetofend(struct ordinary, group.last)
};
'

fn require(value bool, message string) ! {
	if !value { return error(message) }
}

fn expected_facts() []u64 {
	return [u64(16), 8, 8, 0, 8, 8, 0, 1, 0, 8, 32, 8, 8, 16, 24, 16, 11, 1, 1, 2, 10, 9, 96, 32,
		32, 40, 64, 32, 16, 24, 8, 24]
}

fn facts_bytes() []u8 {
	mut result := []u8{}
	for value in expected_facts() {
		for shift in 0 .. 8 { result << u8(value >> (shift * 8)) }
	}
	return result
}

fn compile_case(work string, tag string, source_text string, argv []string,
	expected bool, needle string, required []string, environment map[string]string) !json2.Any {
	source := os.join_path(work, tag + '.c')
	obj := os.join_path(work, tag + '.o')
	dep := obj + '.d'
	preprocessed := obj + '.i'
	os.write_file(source, source_text)!
	preprocess := [...argv, '-E', '-dD', '-MD', '-MF', dep, '-MQ', obj, source, '-o', preprocessed]
	hosttest.command(preprocess, obj + '.preprocess.log', 120, environment)!
	dependencies := hosttest.dependency_paths(os.read_file(dep)!, obj)!
	before := hosttest.hashes(dependencies)!
	for path in required {
		require(hosttest.resolve_path(path)! in before, 'Missing actual compiler dependency: ' + path)!
	}
	// Keep exact bytes, including system/compiler headers, for later review even
	// when another session subsequently changes an unrelated shared header.
	for path, checksum in before {
		snapshot := os.join_path(work, 'input-snapshots', checksum)
		if !os.exists(snapshot) { os.cp(path, snapshot)! }
		require(hosttest.sha(snapshot)! == checksum, 'Compiler input snapshot differs')!
	}
	command := [...argv, '-c', source, '-o', obj]
	result := hosttest.capture(command, obj + '.compile.log', 120, environment)!
	require((result.code == 0) == expected, 'Unexpected result: ' + tag + '; see ' + obj + '.compile.log')!
	if !expected {
		require(result.stderr.contains(needle), 'Unrelated negative diagnostic: ' + tag + '; see compile log')!
	}
	mut imports := ''
	mut object_hash := ''
	mut facts_hash := ''
	if expected {
		imports = hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', obj],
			obj + '.imports.log', 30, environment)!.stdout
		require(imports.trim_space() == '', 'Declarative object imports a runtime: ' + imports)!
		data := obj + '.rodata'
		hosttest.command([hosttest.tool('llvm-objcopy'), '--dump-section', '.rodata=' + data, obj],
			obj + '.objcopy.log', 30, environment)!
		require(os.read_bytes(data)! == facts_bytes(), 'Original/production ABI facts differ: ' + tag)!
		facts_hash = hosttest.sha(data)!
		// llvm-objcopy may rewrite its input even for --dump-section. Bind
		// the final saved object, after the ABI bytes have been extracted.
		object_hash = hosttest.sha(obj)!
	}
	require(before == hosttest.hashes(dependencies)!, 'Compiler dependency changed during validation')!
	return {
		'tag':                    json2.Any(tag)
		'compiler_argv':          hosttest.strings(command)
		'preprocess_argv':        hosttest.strings(preprocess)
		'expected_success':       expected
		'exit':                   result.code
		'diagnostic_needle':      needle
		'source':                 source
		'source_sha256':          hosttest.sha(source)!
		'object':                 obj
		'object_sha256':          object_hash
		'facts_sha256':           facts_hash
		'preprocessed_sha256':    hosttest.sha(preprocessed)!
		'dependency_file_sha256': hosttest.sha(dep)!
		'dependency_sha256':      hosttest.string_map(before)
		'compile_log_sha256':     hosttest.sha(obj + '.compile.log')!
		'preprocess_log_sha256':  hosttest.sha(obj + '.preprocess.log')!
		'runtime_imports':        imports
	}
}

fn control_body(name string) string {
	return match name {
		'raw_union_fam' { 'union raw { unsigned long values[]; };\n' }
		'duplicate_fam_name' {
			'union duplicate { DECLARE_FLEX_ARRAY(unsigned char, values); DECLARE_FLEX_ARRAY(unsigned long, values); };\n'
		}
		'duplicate_group_field' {
			'struct duplicate { unsigned first; struct_group(group, unsigned first;); };\n'
		}
		'incomplete_fam_size' {
			'struct incomplete { DECLARE_FLEX_ARRAY(unsigned long, values); };\nconst unsigned long bad = sizeof_field(struct incomplete, values);\n'
		}
		'one_element_fam' {
			'#undef DECLARE_FLEX_ARRAY\n#define DECLARE_FLEX_ARRAY(TYPE, NAME) struct { struct {} __empty_ ## NAME; TYPE NAME[1]; }\n' + layout
		}
		'named_group_only' {
			'#undef __struct_group\n#define __struct_group(TAG, NAME, ATTRS, MEMBERS...) struct TAG { MEMBERS } ATTRS NAME\n' + layout
		}
		'lost_attributes' {
			'#undef struct_group_attr\n#define struct_group_attr(NAME, ATTRS, MEMBERS...) __struct_group(, NAME, , MEMBERS)\n' + layout
		}
		else {
			'#undef struct_group_tagged\n#define struct_group_tagged(TAG, NAME, MEMBERS...) __struct_group(, NAME, , MEMBERS)\n' + layout
		}
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
	require(hosttest.file_digest(archive)! == pin['sha256']!.str(), 'Pinned archive differs')!
	work := hosttest.work_dir(keep, 'vinix-stddef-layout-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	os.mkdir_all(os.join_path(work, 'input-snapshots'))!
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	require(compiler.len > 0, 'Compiler command is empty')!
	compiler_path := os.real_path(os.find_abs_path_of_executable(compiler[0])!)
	tool_paths := [compiler_path, os.real_path(hosttest.tool('llvm-nm')),
		os.real_path(hosttest.tool('llvm-objcopy'))]
	tool_hashes := hosttest.hashes(tool_paths)!
	environment := os.environ()
	version := hosttest.command([...compiler, '--version'], os.join_path(work, 'compiler-version.log'),
		30, environment)!.stdout
	production_path := os.join_path(here, 'include/linux/stddef.h')
	production := os.read_file(production_path)!
	original_path := os.join_path(linux, 'include/linux/stddef.h')
	uapi_path := os.join_path(linux, 'include/uapi/linux/stddef.h')
	paths := ['include/linux/stddef.h', 'include/uapi/linux/stddef.h']
	members := paths.map('linux-' + pin['version']!.str() + '/' + it)
	extracted := hosttest.archive_members(archive, members)!
	mut refs := map[string]string{}
	for i, path in paths {
		data := extracted[members[i]] or { return error('Missing pinned member: ' + path) }
		require(data == os.read_bytes(os.join_path(linux, path))!, 'Original header differs from archive')!
		dest := os.join_path(work, 'reference', path)
		os.mkdir_all(os.dir(dest))!
		os.write_file(dest, data.bytestr())!
		refs[path] = hosttest.sha(dest)!
	}
	original := os.read_file(original_path)!
	mut macros := map[string]string{}
	for name in ['sizeof_field', 'offsetofend', 'struct_group', 'struct_group_attr',
		'struct_group_tagged', 'DECLARE_FLEX_ARRAY'] {
		pinned := smpfixture.macros(original, name)!
		actual := smpfixture.macros(production, name)!
		require(pinned.len == 1 && actual == pinned, 'Wrapper differs from exact pinned owner: ' + name)!
		macros[name] = pinned[0]
	}
	require(production.count('#include <uapi/linux/stddef.h>\n') == 1
		&& production.count('#include <stddef.h>\n') == 1 && !production.contains('enum')
		&& !production.contains('#define NULL') && !production.contains('#define offsetof('),
		'Native standard/Boolean declaration ownership changed')!
	require(!os.exists(os.join_path(here, 'include/uapi/linux/stddef.h')),
		'The genuine UAPI implementation was shadowed')!
	mut guarded := [@FILE, production_path, original_path, uapi_path,
		os.join_path(here, 'upstream.json'), os.join_path(root, 'tests/linuxkpi/smpfixture/core.v')]
	guarded << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	before := hosttest.hashes(guarded)!
	include := os.join_path(work, 'include')
	hosttest.audit_headers(include)!
	old_path := os.join_path(work, 'before-stddef.h')
	os.write_file(old_path, prior_header)!
	mut records := []json2.Any{}
	for target in ['x86_64-unknown-none', 'aarch64-unknown-none'] {
		for standard in ['gnu99', 'gnu11'] {
			flags := [...compiler, ...smpfixture.flags(linux, include, target, standard)]
			guard := if target.starts_with('x86') {
				'_Static_assert(__x86_64__ == 1, "actual x86 target compiler");\n'
			} else {
				'_Static_assert(__aarch64__ == 1, "actual ARM target compiler");\n'
			}
			for profile in ['original', 'production'] {
				includes := if profile == 'original' {
					'#include "' + original_path + '"\n'
				} else {
					'#include <linux/stddef.h>\n'
				}
				required := [uapi_path,
					if profile == 'original' { original_path } else { production_path }]
				tag := target + '-' + standard + '-' + profile
				records << compile_case(work, tag, includes + guard + layout, flags, true, '', required, environment)!
				for control in ['raw_union_fam', 'duplicate_fam_name', 'duplicate_group_field',
					'incomplete_fam_size', 'one_element_fam', 'named_group_only', 'lost_attributes',
					'lost_tag'] {
					needle := match control {
						'raw_union_fam' { 'flexible array member' }
						'duplicate_fam_name' { '__empty_values' }
						'duplicate_group_field' { 'redeclares' }
						'one_element_fam' { 'static assertion failed' }
						'named_group_only' { 'no member named' }
						'lost_attributes' { 'packed attributes preserved' }
						else { 'incomplete type' }
					}
					mut selected := flags.clone()
					// GNU accepts a raw union FAM as an extension; rejection here
					// explicitly enables the matching extension diagnostic.
					if control == 'raw_union_fam' {
						selected << '-Werror=gnu-flexible-array-union-member'
					}
					records << compile_case(work, tag + '-' + control, includes + guard + control_body(control),
						selected, false, needle, required, environment)!
				}
				// This deliberately wrong complete zero-array passes every outer
				// layout assertion. Only the genuine incomplete-size rejection
				// above distinguishes its type from an original flexible member.
				fake := '#undef DECLARE_FLEX_ARRAY\n#define DECLARE_FLEX_ARRAY(TYPE, NAME) struct { struct {} __empty_ ## NAME; TYPE NAME[0]; }\n'
				records << compile_case(work, tag + '-zero-array-false-positive', includes + guard + fake + layout +
					'_Static_assert(sizeof_field(struct flex_tail, values) == 0, "false complete zero array");\n',
					flags, true, '', required, environment)!
			}
			for order in [0, 1, 2] {
				includes := match order {
					0 {
						'#include <stdbool.h>\n#include <linux/stddef.h>\n#include <linux/stddef.h>\n#include <uapi/linux/stddef.h>\n#include <uapi/linux/stddef.h>\n'
					}
					1 {
						'#include <linux/stddef.h>\n#include <stdbool.h>\n#include <linux/stddef.h>\n#include <uapi/linux/stddef.h>\n'
					}
					else {
						'#include <uapi/linux/stddef.h>\n#include <linux/stddef.h>\n#include <stdbool.h>\n#include <uapi/linux/stddef.h>\n#include <linux/stddef.h>\n'
					}
				}
				body := '_Static_assert(true == 1 && false == 0 && __bool_true_false_are_defined == 1, "native bool constants");\n_Static_assert(__builtin_types_compatible_p(bool, _Bool) && sizeof(bool) == 1, "native bool identity");\n'
				records << compile_case(work, target + '-' + standard + '-bool-order-' + order.str(),
					includes + guard + body + layout, flags, true, '', [
						production_path,
						uapi_path,
						os.join_path(root, 'kernel/freestnd-c-hdrs/stdbool.h'),
					], environment)!
			}
			regression := '#include "' + old_path + '"\n' + guard +
				'union regression { unsigned long scalar; DECLARE_FLEX_ARRAY(unsigned long, values); };\n'
			records << compile_case(work, target + '-' + standard + '-historical-missing-wrapper', regression,
				flags, false, 'DECLARE_FLEX_ARRAY', [old_path], environment)!
			println(target + ' ' + standard + ': original/production layouts, incomplete FAM controls and native bool ordering passed')
		}
	}
	require(records.len == 96, 'Maintained declaration matrix omitted cases')!
	mut success := 0
	for record in records { if record.as_map()['expected_success']!.bool() { success++ } }
	require(success == 28, 'Unexpected successful declaration-object count')!
	require(before == hosttest.hashes(guarded)!, 'Source changed during declaration validation')!
	require(tool_hashes == hosttest.hashes(tool_paths)!, 'Compiler/object tool changed during validation')!
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(os.join_path(work, 'result.json'), {
		'scope':                     json2.Any(scope)
		'source_sha256':             hosttest.string_map(before)
		'archive_sha256':            hosttest.file_digest(archive)!
		'original_header_sha256':    hosttest.string_map(refs)
		'exact_wrapper_macros':      hosttest.string_map(macros)
		'compiler_argv':             hosttest.strings(compiler)
		'compiler_path':             compiler_path
		'compiler_version':          version
		'tool_sha256':               hosttest.string_map(tool_hashes)
		'cases':                     records
		'case_count':                records.len
		'successful_objects':        success
		'expected_rejections':       records.len - success
		'facts_words':               expected_facts().map(json2.Any(it))
		'facts_sha256':              hosttest.text_sha(facts_bytes().bytestr())
		'historical_header_sha256':  hosttest.sha(old_path)!
		'raw_union_rejection_scope': 'Explicit -Werror=gnu-flexible-array-union-member; ordinary GNU flags may accept the extension.'
	})!
	println('PASS: 96 declaration controls, 28 runtime-import-free objects, 32 identical LP64 facts; no runtime support claim')
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: stddef_layout.v [--keep-dir NEW]', scope) or {
		eprintln(err)
		exit(2)
	}
	run_profile(keep) or {
		eprintln(err)
		exit(1)
	}
}
