// SPDX-License-Identifier: GPL-2.0-or-later
// Genuine pinned instruction helpers, compiler opcodes and unresolved service imports.
module main

import os
import json2
import strconv
import crypto.sha256
import hosttest
import insnfixture

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn tool(name string) !string {
	path := hosttest.tool(name)
	require(os.is_file(path), 'Missing object inspection tool: ' + name)!
	return path
}

fn inspect(argv []string) !string {
	result := hosttest.capture(argv, '', -1, os.environ())!
	require(result.code == 0, result.stderr)!
	return result.stdout
}

fn original_headers(work string, linux string, archive string, pin map[string]json2.Any) !map[string]json2.Any {
	require(hosttest.file_digest(archive)! == pin['sha256']!.str(), 'Instruction headers require the exact pinned archive')!
	prefix := 'linux-' + pin['version']!.str() + '/'
	members := hosttest.archive_members(archive, insnfixture.originals.map(prefix + it))!
	mut records := map[string]json2.Any{}
	for name in insnfixture.originals {
		bytes := members[prefix + name] or { return error('Missing original instruction header: ' + name) }
		require(bytes == os.read_bytes(os.join_path(linux, name))!, 'Imported instruction header differs: ' + name)!
		target := os.join_path(work, 'originals', name)
		os.mkdir_all(os.dir(target))!
		os.write_file_array(target, bytes)!
		records[name] = map[string]json2.Any{
			'archive_member': json2.Any(prefix + name)
			'sha256':         hosttest.file_digest(target)!
		}
	}
	special := os.read_file(os.join_path(linux, insnfixture.originals[1]))!
	start := special.index('static inline void movdir64b(') or { return error('Missing original MOVDIR64B helper') }
	remaining := special[start..]
	newline := remaining.index('\n') or { return error('Incomplete original MOVDIR64B helper') }
	require(remaining[newline..].starts_with('\n{'), 'Original MOVDIR64B helper body changed')!
	end := remaining.index('\n}') or { return error('Unclosed original MOVDIR64B helper') }
	helper := remaining[..end + 2]
	asm_start := helper.index('asm volatile(".byte ') or { return error('Missing original MOVDIR64B opcode') }
	byte_string := helper[asm_start + 'asm volatile(".byte '.len..].all_before('"')
	mut words := []string{}
	for value in byte_string.split(',') {
		number := strconv.parse_uint(value.trim_space().all_after('0x'), 16, 64)!
		require(number <= 255, 'Original instruction byte exceeds one byte')!
		word := strconv.format_uint(number, 16)
		words << '0'.repeat(2 - word.len) + word
	}
	opcode := words.join(' ')
	require(opcode == '66 0f 38 f8 02' && helper.contains('"+m" (*__dst)') && helper.contains('"m" (*__src)'), 'Original 64-byte memory operands/instruction changed')!
	require(os.read_file(os.join_path(linux, insnfixture.originals[0]))!.contains('#include <asm/special_insns.h>'), 'Original processor instruction dependency changed')!
	return {
		'archive_sha256':          pin['sha256']!
		'headers':                 json2.Any(records)
		'movdir64b_helper_sha256':  sha256.sum(helper.bytes()).hex()
		'instruction_bytes':       opcode
	}
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	here := hosttest.upstream_here()
	pin := hosttest.upstream_pin()!
	linux := hosttest.resolve_path(hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(hosttest.upstream_default(), 'linux-' + pin['version']!.str())))!
	hosttest.verify_upstream(linux, pin)!
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	nm := tool(hosttest.env_default('NM', 'llvm-nm'))!
	objdump := tool(hosttest.env_default('OBJDUMP', 'llvm-objdump'))!
	work := hosttest.work_dir(keep, 'vinix-special-insns-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	archive := os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	original := original_headers(work, linux, archive, pin)!
	processor := os.join_path(here, 'include/asm/processor.h')
	mut prior := os.read_file(processor)!
	for header in insnfixture.includes {
		directive := '#include <' + header + '>\n'
		require(prior.count(directive) == 1, 'Missing/duplicated genuine dependency ' + header)!
		prior = prior.replace(directive, '')
	}
	baseline := os.join_path(work, 'old-overlay/asm/processor.h')
	os.mkdir_all(os.dir(baseline))!
	os.write_file(baseline, prior)!
	generated := os.join_path(work, 'include')
	hosttest.audit_headers(generated)!
	mut flags := ['--target=x86_64-unknown-none', '-std=gnu11', '-O2', '-ffreestanding', '-fwrapv',
		'-nostdinc', '-mno-red-zone', '-mcmodel=kernel', '-fno-PIC', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-parameter', '-Wno-unused-function', '-D__KERNEL__', '-include', 'linux/kconfig.h',
		'-include', os.join_path(linux, 'include/linux/compiler_types.h'), '-isystem',
		os.join_path(root, 'kernel/freestnd-c-hdrs')]
	for path in [generated, os.join_path(here, 'include'), os.join_path(root, 'kernel/c'),
		os.join_path(linux, 'include'), os.join_path(linux, 'include/uapi'),
		os.join_path(linux, 'arch/x86/include'), os.join_path(linux, 'arch/x86/include/uapi')] { flags << ['-I', path] }
	bounds := os.join_path(generated, 'generated/bounds.h')
	// Keep the original shlex.join round trip before the bounds generator.
	compiler_text := compiler.map(shell_word(it)).join(' ')
	raw := hosttest.generate_bounds(linux, archive, bounds, bounds + '.d', bounds + '.json', compiler_text, flags)!
	provenance := hosttest.decode_json(hosttest.bounds_metadata_json(raw))!
	mut positives := []json2.Any{}
	mut rejected := []json2.Any{}
	for dialect in ['gnu99', 'gnu11'] {
		options := flags.map(if it.starts_with('-std=') { '-std=' + dialect } else { it })
		for name, body in insnfixture.probes {
			source := os.join_path(work, dialect + '-' + name + '.c')
			output := source.all_before_last('.') + '.o'
			dependency := source.all_before_last('.') + '.d'
			os.write_file(source, insnfixture.declarations + body)!
			argv := [...compiler, ...options, '-MD', '-MF', dependency, '-c', source, '-o', output]
			result := hosttest.capture(argv, '', -1, os.environ())!
			os.write_file(source.all_before_last('.') + '.log', result.stderr)!
			require(result.code == 0, name + ':\n' + result.stderr)!
			symbols := inspect([nm, output])!
			undefined := inspect([nm, '--undefined-only', output])!
			mut imports := []string{}
			for line in undefined.split_into_lines() { words := line.fields(); if words.len > 0 { imports << words.last() } }
			imports.sort()
			require(imports == insnfixture.imports[name], 'Unexpected unresolved symbols in ' + name + ': ' + imports.str())!
			require(name != 'declarations' || symbols.trim_space() == '', 'Declaration-only header emitted symbols')!
			assembly := inspect([objdump, '-d', output])!
			os.write_file(source.all_before_last('.') + '.disassembly', assembly)!
			emitted := assembly.contains(original['instruction_bytes']!.str())
			require(emitted == (name in ['movdir-call', 'movdir-address', 'iosubmit-one', 'iosubmit-count']), 'Unexpected MOVDIR64B opcode in ' + name)!
			sections := inspect([objdump, '--section-headers', output])!
			require(sections.contains('.altinstructions') == (name == 'alternative-references'), 'Original alternative sections changed: ' + name)!
			mut inputs := hosttest.hashes(hosttest.dependency_paths(os.read_file(dependency)!, output)!)!
			inputs[source] = hosttest.file_digest(source)!
			positives << json2.Any(map[string]json2.Any{
				'probe':              json2.Any(name)
				'standard':           dialect
				'argv':               hosttest.strings(argv)
				'input_sha256':       hosttest.string_map(inputs)
				'object_sha256':      hosttest.file_digest(output)!
				'unresolved_symbols': hosttest.strings(imports)
				'undefined_symbols':  undefined
				'symbols':            symbols
				'assembly_sha256':    sha256.sum(assembly.bytes()).hex()
				'sections':           sections
			})
		}
		for name, control in insnfixture.negative {
			source := os.join_path(work, dialect + '-' + name + '.c')
			os.write_file(source, control.code)!
			mut extra := []string{}
			if name == 'old-processor' { extra << ['-I', os.join_path(work, 'old-overlay')] }
			argv := [...compiler, ...extra, ...options, '-c', source, '-o', source.all_before_last('.') + '.o']
			result := hosttest.capture(argv, '', -1, os.environ())!
			os.write_file(source.all_before_last('.') + '.log', result.stderr)!
			require(result.code != 0 && control.errors.all(result.stderr.contains(it)), 'Original missing-dependency probe did not fail: ' + name)!
			rejected << json2.Any(map[string]json2.Any{
				'probe':       json2.Any(name)
				'standard':    dialect
				'argv':        hosttest.strings(argv)
				'exit':        result.code
				'diagnostics': result.stderr
			})
		}
	}
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':           json2.Any(insnfixture.scope)
		'linux_version':   pin['version']!
		'originals':       original
		'bounds':          provenance
		'source_sha256':   hosttest.string_map(hosttest.hashes([processor, @FILE])!)
		'probes':          positives
		'rejected_probes': rejected
	})!
	println('special instruction headers: 16 compiler objects and 4 rejected probes passed; no runtime claim')
}

fn shell_word(word string) string {
	if word != '' && word.bytes().all(it.is_alnum() || it in [`_`, `@`, `%`, `+`, `=`, `:`, `,`, `.`, `/`, `-`]) { return word }
	return "'" + word.replace("'", "'\"'\"'") + "'"
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: special_insns.v [--keep-dir DIRECTORY]', insnfixture.scope) or { eprintln(err.msg()); exit(2) }
	run_profile(keep) or { eprintln(err.msg()); exit(1) }
}
