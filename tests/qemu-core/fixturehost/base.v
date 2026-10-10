// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import hosttest
import json2
import os

const base_ranges = [LineRange{88, 168}, LineRange{282, 377}, LineRange{450, 542}]
const base_exports = ['reap_ok', 'verify_marker', 'verify_persistence_boot', 'test_random', 'test_cow',
	'test_sparse_tmpfs_shared_mapping', 'test_partial_munmap_reclaims_pages',
	'test_madvise_reclaims_anonymous_pages', 'test_short_lived_process_memory_reclamation',
	'test_forked_cow_memory_reclamation']

// Replace C identifiers, without changing larger names, declarations or bodies.
fn rename_identifiers(text string, names []string) string {
	mut result := ''
	mut start := 0
	for i, ch in (text + ' ').bytes() {
		if hosttest.word_char(ch) { continue }
		word := text[start..i]
		result += if word in names { 'original_' + word } else { word }
		if i < text.len { result += ch.ascii_str() }
		start = i + 1
	}
	return result
}

fn base_sources(source string) (string, string) {
	lines := original_lines(source)
	mut reference_text := '#include "basefixture_v_contract.h"\n#line 52 "test.c"\n' + lines[51..72].join('')
	mut ported := '#line 1 "test.c"\n'
	mut previous := 0
	for span in base_ranges {
		mut section := lines[span.first - 1..span.last].join('')
		for name in base_exports {
			section = section.replace('static int ' + name + '(', 'int ' + name + '(')
		}
		reference_text += '#line ' + span.first.str() + ' "test.c"\n' + section
		ported += lines[previous..span.first - 1].join('') + '#line ' + (span.last + 1).str() + ' "test.c"\n'
		previous = span.last
	}
	ported += lines[previous..].join('')
	ported = ported.replace_once('#include <unistd.h>\n', '#include <unistd.h>\n#include "basefixture-api.h"\n#line 51 "test.c"\n')
	return reference_text, ported
}

pub fn generate_base(output string, arch string) ! {
	outside_checkout(output, 'Recover frozen C outside the maintained checkout')!
	mkdir_all(output)!
	stage := output + '/basefixture'
	stage_pending(hosttest.root() + '/tests/qemu-core/basefixture', stage)!
	hosttest.generate_module(stage, output + '/basefixture.c', arch, []string{})!
	hosttest.emit_module_header(stage, output + '/basefixture.c', output + '/basefixture-api.h')!
}

pub fn prepare_base(output string, arch string) ! {
	generate_base(output, arch)!
	original := original_source()!
	write(output + '/original-test.c', original)!
	reference_text, ported := base_sources(original)
	write(output + '/original-base.c', reference_text)!
	write(output + '/ported-test.c', ported)!
	stage_pending(hosttest.root() + '/tests/qemu-core/baseoracle', output + '/baseoracle')!
	header := rename_identifiers(read(output + '/basefixture-api.h')!, base_exports)
		.replace('VINIX_GENERATED_BASEFIXTURE_API_H', 'VINIX_GENERATED_ORIGINAL_BASEFIXTURE_API_H')
	write(output + '/original-basefixture-api.h', header)!
	// Paths are sorted just as the original recursive source receipt was.
	mut paths := os.walk_ext(output, '')
	paths.sort()
	mut hashes := map[string]json2.Any{}
	for path in paths {
		if os.file_ext(path) !in ['.v', '.h', '.c', '.S'] { continue }
		hashes[path[output.trim_right('/').len + 1..]] = hosttest.sha(path)!
	}
	receipt := json2.Any({
		'revision':             json2.Any(reference)
		'path':                 reference_path
		'blob':                 reference_blob
		'sha256':               reference_sha
		'original_line_ranges': json2.Any(base_ranges.map(json2.Any([
			json2.Any(it.first),
			json2.Any(it.last),
		])))
		'original_lines':       270
		'baseline_adaptation':  'Only function linkage changes, compiler name remapping and exact original #line directives; no body or expectation edits.'
		'source_sha256':        hashes
	})
	write_schema(output + '/original-source.json', receipt)!
}

pub fn host_base(output string, cc string, arch string, native_headers string) ! {
	outside_checkout(output, 'Recover frozen C outside the maintained checkout')!
	mkdir_all(os.dir(output))!
	generator := hosttest.env_default('VINIX_QEMU_BASE_GENERATOR', hosttest.root() + '/tests/qemu-core/compile-basefixture')
	command([generator, output, '--arch', arch], os.dir(output) + '/prepare.log')!
	hosttest.generate_module(output + '/baseoracle', output + '/baseoracle.c', arch, []string{})!
	target := target_flags(arch, false)
	mut flags := [cc, ...target, '-O1', '-g', '-Wall', '-Wextra', '-Werror', ...ignored_warnings,
		'-fno-strict-aliasing', '-fsanitize=address,undefined', '-I', output, '-I',
		output + '/basefixture']
	if native_headers != '' { flags << ['-idirafter', native_headers] }
	mut prefix := '#include "oracle-native-abi.h"\n'
	for name in ['sysinfo', 'open', 'unlink', 'madvise', 'execv'] {
		prefix += '#define ' + name + '(...) vqc_host_' + name + '(__VA_ARGS__)\n'
	}
	for name in ['original-base', 'basefixture'] {
		write(output + '/host-' + name + '.c', prefix + read(output + '/' + name + '.c')!)!
	}
	flags << ['-I', output + '/baseoracle']
	mut objects := []string{}
	for i, name in ['original-base', 'basefixture', 'baseoracle'] {
		object := output + '/' + name + '.o'
		source := output + '/' + if name == 'baseoracle' { name } else { 'host-' + name } + '.c'
		defines := if name == 'original-base' {
			base_exports.map('-D' + it + '=original_' + it)
		} else {
			[]string{}
		}
		command([...flags, ...defines, '-c', source, '-o', object], output + '/' + [
			'original',
			'v',
			'oracle',
		][i] + '-compile.log')!
		objects << object
		if name != 'original-base' { check_imports(name, output)! }
	}
	entry := output + '/open-abi.o'
	command([cc, ...target, '-c', output + '/baseoracle/open_abi.S', '-o', entry], '')!
	objects << entry
	program := output + '/basefixture-host'
	command([cc, ...target, '-fsanitize=address,undefined', ...objects, '-o', program], '')!
	result := command([program], output + '/host.log')!
	for marker in ['QEMU CORE BASE DIFFERENTIAL PASS', 'QEMU CORE MEMORY DIFFERENTIAL PASS'] {
		if !result.contains(marker) { return error('Missing differential marker: ' + marker) }
	}
	mut receipt := hosttest.decode_json('{"result":"PASS","host":"","base_cases":{"random_api_inputs":5,"marker_boundaries":14,"actual_fork_cow":1},"memory_cases":{"success":5,"sysinfo_failures":14},"native_requests":"return, errno, sysinfo count and API request trace compared","ownership":"real fork/private/shared mappings; cases isolated in processes and joined before records expire","native_boundary":"Linux free-memory timeline, private anonymous discard and successful exec modeled on Darwin; real native guest validates kernel accounting and exec image","source_receipt":"original-source.json","implicit_allocator_imports":[],"executable_sha256":""}')!.as_map()
	receipt['host'] = command(['uname', '-srm'], '')!.trim_space()
	receipt['executable_sha256'] = hosttest.sha(program)!
	write_schema(output + '/validation.json', receipt)!
	println('QEMU-core base/memory C/V native host differential: PASS')
}
