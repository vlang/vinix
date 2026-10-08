// SPDX-License-Identifier: GPL-2.0-or-later
// Original x86 page/entry types and UAPI aliases; compiler ABI only.
module main

import os
import json2
import hosttest
import typefixture

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	here := hosttest.upstream_here()
	pin := hosttest.upstream_pin()!
	linux := hosttest.resolve_path(hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(hosttest.upstream_default(), 'linux-' + pin['version']!.str())))!
	archive := os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	compiler_text := hosttest.env_default('CC', 'clang')
	compiler := hosttest.shell_split(compiler_text)!
	work := hosttest.work_dir(keep, 'vinix-pgtable-types-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	include := os.join_path(work, 'include')
	hosttest.audit_headers(include)!
	source := os.join_path(work, 'page-types.c')
	os.write_file(source, typefixture.c_test)!
	before := os.join_path(work, 'before/include/asm')
	os.mkdir_all(before)!
	header := os.join_path(here, 'include/asm/processor.h')
	original_header := os.read_file(header)!
	require(original_header.contains('#include <asm/pgtable_types.h>\n'), 'Production processor header does not restore original types')!
	os.write_file(os.join_path(before, 'processor.h'), original_header.replace('#include <asm/pgtable_types.h>\n', ''))!
	mut results := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		mut flags := ['--target=x86_64-unknown-none', '-std=' + standard, '-O2', '-ffreestanding',
			'-fwrapv', '-nostdinc', '-mno-red-zone', '-mcmodel=kernel', '-fno-PIC', '-Wall', '-Wextra',
			'-Werror', '-Wno-unused-parameter', '-Wno-unused-function', '-D__KERNEL__', '-include',
			'linux/kconfig.h', '-include', os.join_path(linux, 'include/linux/compiler_types.h'),
			'-isystem', os.join_path(root, 'kernel/freestnd-c-hdrs')]
		for path in [include, os.join_path(here, 'include'), os.join_path(root, 'kernel/c'),
			os.join_path(linux, 'include'), os.join_path(linux, 'include/uapi'),
			os.join_path(linux, 'arch/x86/include'), os.join_path(linux, 'arch/x86/include/uapi')] {
			flags << ['-I', path]
		}
		bounds := os.join_path(include, 'generated/bounds.h')
		raw := hosttest.generate_bounds(linux, archive, bounds, bounds + '.d', bounds + '.json', compiler_text, flags)!
		provenance := hosttest.decode_json(hosttest.bounds_metadata_json(raw))!
		mut orders := []json2.Any{}
		for order in ['kernel-first', 'uapi-first'] {
			tag := standard + '-' + order
			ordered_source := os.join_path(work, tag + '.c')
			os.write_file(ordered_source, if order == 'uapi-first' { '#include <uapi/linux/types.h>\n' + typefixture.c_test } else { typefixture.c_test })!
			obj := os.join_path(work, tag + '.o')
			dependencies := os.join_path(work, tag + '.d')
			argv := [...compiler, ...flags, '-MD', '-MF', dependencies, '-MQ', obj, '-c', ordered_source, '-o', obj]
			compiled := hosttest.capture(argv, '', -1, os.environ())!
			os.write_file(os.join_path(work, tag + '-compile.log'), compiled.stdout + compiled.stderr)!
			require(compiled.code == 0, 'Configured original page types do not compile:\n' + compiled.stderr)!
			inspected := hosttest.capture([hosttest.env_default('NM', 'nm'), '-u', obj], '', -1, os.environ())!
			require(inspected.code == 0, inspected.stderr)!
			imports := inspected.stdout
			os.write_file(os.join_path(work, tag + '-imports.log'), imports)!
			require(imports.trim_space() == '', 'Type/value helpers unexpectedly import a runtime:\n' + imports)!
			inputs := hosttest.dependency_paths(os.read_file(dependencies)!, obj)!
			for original in ['include/linux/mm_types.h', 'arch/x86/include/asm/pgtable_types.h',
				'include/uapi/linux/types.h', 'include/asm-generic/int-ll64.h', 'include/uapi/asm-generic/int-ll64.h'] {
				path := hosttest.resolve_path(os.join_path(linux, original))!
				require(path in inputs, 'Test did not compile the real original header: ' + path)!
			}
			orders << json2.Any(map[string]json2.Any{
				'include_order':   json2.Any(order)
				'argv':            hosttest.strings(argv)
				'object_sha256':   hosttest.file_digest(obj)!
				'runtime_imports': imports
				'input_sha256':    hosttest.string_map(hosttest.hashes(inputs)!)
			})
		}
		before_argv := [...compiler, '-I', os.dir(before), ...flags, '-fsyntax-only', source]
		rejected := hosttest.capture(before_argv, '', -1, os.environ())!
		os.write_file(os.join_path(work, standard + '-before.log'), rejected.stderr)!
		require(rejected.code != 0 && rejected.stderr.contains("unknown type name 'pgtable_t'"), 'Missing-include regression did not expose pgtable_t:\n' + rejected.stderr)!
		results << json2.Any(map[string]json2.Any{
			'standard':                 json2.Any(standard)
			'bounds':                   provenance
			'missing_include_rejected': rejected.code
			'include_orders':           orders
		})
		println(standard + ': original page/entry types and UAPI aliases in both include orders passed; no runtime imports')
	}
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':                   json2.Any('Native-target compiler ABI only. Original page/folio/ptdesc records and configured x86 entry types; no Linux page allocation, refs, page-table installation, DMA or GPU runtime is supplied.')
		'linux_version':           pin['version']!
		'processor_header_sha256': hosttest.file_digest(header)!
		'test_sha256':             hosttest.file_digest(@FILE)!
		'results':                 results
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: pgtable_types.v [--keep-dir DIRECTORY]', scope) or { eprintln(err.msg()); exit(2) }
	run_profile(keep) or { eprintln(err.msg()); exit(1) }
}

const scope = 'Check the configured original x86 page-table and complete page types. Compile real native-target GNU99/GNU11 objects, using the production processor header, original mm_types.h and freshly generated compiler adapters/bounds. This restores compiler ABI only; no page allocation or DMA runtime is tested.'
