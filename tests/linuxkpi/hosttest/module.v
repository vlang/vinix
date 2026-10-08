// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

import os

// Match the original nm allocation guard's word boundaries on both Darwin's
// bare undefined names and ELF's address/type/name lines.
pub fn allocation_symbols(text string) bool {
	mut token := ''
	for ch in (text + ' ').bytes() {
		if word_char(ch) { token += ch.ascii_str(); continue }
		name := if token.starts_with('_') { token[1..] } else { token }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup'] || name.starts_with('new_array') { return true }
		token = ''
	}
	return false
}

fn foreign_type(text string, name string) !string {
	needle := 'struct C.' + name
	mut matches := []string{}
	mut start := 0
	for start < text.len {
		position := start + (text[start..].index(needle) or { break })
		mut brace := position + needle.len
		for brace < text.len && text[brace].is_space() { brace++ }
		if brace < text.len && text[brace] == `{` {
			end := brace + (text[brace..].index('}') or { return error('Unclosed native declaration: ' + name) }) + 1
			prefix := text[..position].trim_right(' \t\r\n\v\f')
			begin := if prefix.ends_with('@[typedef]') { prefix.len - '@[typedef]'.len } else { position }
			matches << text[begin..end].clone()
		}
		start = position + needle.len
	}
	if matches.len != 1 { return error('Expected exactly one native ' + name + ' declaration') }
	return matches[0]
}

// Stage only the unchanged production algorithms and their original foreign
// declarations when standalone fixtures need no unrelated callback storage.
pub fn generate_header_primitives(output string, arch string, host bool, implementations_only bool) ! {
	mut defines := ['nofloat']
	if host { defines << 'linuxkpi_host_test' }
	source := os.join_path(root(), 'kernel/linuxkpi/headercore')
	if !implementations_only { generate_module(source, output, arch, defines)!; return }
	work := work_dir('', 'vinix-header-implementations-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	isolated := os.join_path(work, 'headercore')
	os.mkdir(isolated)!
	for name in ['primitive.v', 'policy.v'] { os.cp(os.join_path(source, name), os.join_path(isolated, name))! }
	mut declarations := []string{}
	common := os.read_file(os.join_path(source, 'common.v'))!
	for name in ['spinlock_t', 'task_struct'] { declarations << foreign_type(common, name)! }
	declarations << foreign_type(os.read_file(os.join_path(source, 'wait.v'))!, 'atomic_t')!
	os.write_file(os.join_path(isolated, 'native_types.v'), '@[translated]\nmodule headercore\n' +
		'#include "linuxkpi_header_primitive_v_contract.h"\n' + declarations.join('\n') + '\n')!
	generate_module(isolated, output, arch, defines)!
}

fn replace_word(text string, word string, replacement string, prefix bool) string {
	mut result := ''
	mut start := 0
	for start < text.len {
		position := start + (text[start..].index(word) or { break })
		end := position + word.len
		result += text[start..position]
		if (position == 0 || !word_char(text[position - 1])) &&
			(prefix || end == text.len || !word_char(text[end])) { result += replacement }
		else { result += word }
		start = end
	}
	return result + text[start..]
}

pub fn generate_module(source string, output string, arch string, defines []string) ! {
	selected := command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
		'find-v', root()], '', -1, os.environ())!.stdout
	work := work_dir('', 'vinix-v-module-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	name := os.file_name(source)
	os.cp_all(source, os.join_path(work, name), false)!
	mut imported_abiargs := false
	for path in os.glob(os.join_path(source, '*.v'))! {
		for line in os.read_file(path)!.split_into_lines() {
			trimmed := line.trim_left(' \t\r\n\v\f')
			if trimmed.starts_with('import abiargs') {
				tail := trimmed['import abiargs'.len..]
				if tail == '' || tail[0].is_space() { imported_abiargs = true }
			}
		}
	}
	if imported_abiargs { os.cp_all(os.join_path(root(), 'kernel/abiargs'), os.join_path(work, 'abiargs'), false)! }
	os.write_file(os.join_path(work, 'v.mod'), "Module { name: 'native_module' }\n")!
	os.write_file(os.join_path(work, 'entry.v'), 'module main\nimport ${name} as _\n')!
	mut argv := [selected, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix',
		'-arch', arch, '-target-libc-headers', '-gc', 'none', '-manualfree']
	for define in defines { argv << ['-d', define] }
	argv << ['-o', output, work]
	mut env := os.environ(); env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	command(argv, '', -1, env)!
	mut text := scalar_metadata(source, os.read_file(output)!)!
	for symbol in ['_vinit', '_vcleanup', '_vinit_caller', '_vcleanup_caller',
		'_vno_main_init_caller', '_v3_no_main_initialized'] {
		text = replace_word(text, symbol, name + '_' + symbol, false)
	}
	if imported_abiargs { text = replace_word(text, 'abiargs__', name + '__abiargs__', true) }
	if text.split_into_lines().any(it.contains('visibility("default"))) ') && named_body(it, 'backtrace')) {
		text = '#define __V_HAVE_EXECINFO_H 1\n' + text
	}
	os.write_file(output, text)!
}

fn metadata_identifier(text string) bool {
	return text != '' && text.bytes().all(word_char(it))
}

fn readonly_metadata(source string, marker string) !map[string][]string {
	mut result := map[string][]string{}
	mut paths := os.glob(os.join_path(source, '*.v'))!
	paths.sort()
	for path in paths {
		for line in os.read_file(path)!.split_into_lines() {
			if !line.starts_with(marker) { continue }
			value := line[marker.len..].trim_right(' \t\r\n\v\f')
			pieces := value.split('.')
			if pieces.len == 2 && pieces.all(metadata_identifier(it)) {
				mut parameters := result[pieces[0]]
				if pieces[1] !in parameters { parameters << pieces[1] }
				result[pieces[0]] = parameters
			}
		}
	}
	return result
}

fn readonly_parameters(raw string, parameter string, pointer bool) !string {
	mut parts := raw.split(',')
	mut count := 0
	for index, text in parts {
		needle := (if pointer { '** ' } else { '* ' }) + parameter
		if !text.ends_with(needle) { continue }
		before := text[..text.len - needle.len]
		mut start := before.len
		for start > 0 && word_char(before[start - 1]) { start-- }
		if start == before.len { continue }
		typ := before[start..]
		parts[index] = before[..start] + (if pointer { '${typ}* const* ' } else { 'const ${typ}* ' }) + parameter
		count++
	}
	if count != 1 { return error('Readonly metadata does not match exported parameter ${parameter}') }
	return parts.join(',')
}

pub fn emit_module_header(source string, output string, header string) ! {
	mut readonly := readonly_metadata(source, '// ABI readonly: ')!
	mut readonly_pointer := readonly_metadata(source, '// ABI readonly-pointer: ')!
	mut declarations := []string{}
	for line in os.read_file(output)!.split_into_lines() {
		marker := '__attribute__((visibility("default"))) '
		if !line.contains(marker) { continue }
		prototype := line.all_after(marker).all_before(';')
		if !line.all_after(marker).contains(';') || prototype.contains('{') || prototype.contains('}') { continue }
		if !prototype.contains('(') || !prototype.ends_with(')') { return error('Unsupported exported declaration: ${prototype}') }
		before := prototype.all_before('(')
		name := before.all_after_last(' ')
		result := before[..before.len - name.len - 1]
		if !metadata_identifier(name) || result == '' { return error('Unsupported exported declaration: ${prototype}') }
		mut parameters := prototype[before.len + 1..prototype.len - 1]
		for parameter in readonly[name] {
			parameters = readonly_parameters(parameters, parameter, false) or {
				return error('Readonly metadata does not match ${name}.${parameter}')
			}
		}
		readonly.delete(name)
		for parameter in readonly_pointer[name] {
			parameters = readonly_parameters(parameters, parameter, true) or {
				return error('Readonly pointer metadata does not match ${name}.${parameter}')
			}
		}
		readonly_pointer.delete(name)
		mut declaration := '${result} ${name}(${parameters});'
		for vtype, ctype in {'i32':'int32_t', 'u32':'uint32_t', 'i64':'int64_t', 'u64':'uint64_t',
			'i16':'int16_t', 'u16':'uint16_t', 'i8':'int8_t', 'u8':'uint8_t', 'usize':'size_t', 'isize':'intptr_t'} {
			declaration = replace_word(declaration, vtype, ctype, false)
		}
		mut types := [declaration.all_before(name).trim_space()]
		parameter_text := declaration.all_after('(').all_before_last(');')
		for parameter in parameter_text.split(',') {
			trimmed := parameter.trim_space()
			last := trimmed.all_after_last(' ')
			types << if trimmed.contains(' ') && metadata_identifier(last) {
				trimmed[..trimmed.len - last.len - 1].trim_right(' \t')
			} else { trimmed }
		}
		mut allowed := ['void', 'bool', 'char', 'short', 'int', 'long', 'float', 'double',
			'const', 'signed', 'unsigned', 'size_t', 'intptr_t']
		for prefix in ['', 'u'] { for bits in [8,16,32,64] { allowed << '${prefix}int${bits}_t' } }
		mut unknown := []string{}
		for typ in types {
			mut token := ''
			for ch in (typ + ' ').bytes() {
				if word_char(ch) { token += ch.ascii_str() }
				else { if token != '' && token !in allowed && token !in unknown { unknown << token }; token = '' }
			}
		}
		unknown.sort()
		if unknown.len > 0 { return error('Export ${name} requires unsupported public types: ${unknown}') }
		declarations << declaration
	}
	if readonly.len > 0 || readonly_pointer.len > 0 { return error('Readonly metadata names absent exports: ${readonly}, ${readonly_pointer}') }
	if declarations.len == 0 { return error('Module has no exported declarations') }
	mut guard := 'VINIX_GENERATED_'
	for ch in os.file_name(header).to_upper().bytes() { guard += if word_char(ch) { ch.ascii_str() } else { '_' } }
	os.write_file(header, '// Generated from V; do not maintain this build artifact.\n' +
		'#ifndef ${guard}\n#define ${guard}\n' + '#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n' +
		'#ifdef __cplusplus\nextern "C" {\n#endif\n' + declarations.join('\n') +
		'\n#ifdef __cplusplus\n}\n#endif\n#endif\n')!
}
