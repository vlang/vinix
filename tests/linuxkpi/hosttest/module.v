// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

import os

// Match the original nm allocation guard's word boundaries on both Darwin's
// bare undefined names and ELF's address/type/name lines.
pub fn allocation_symbols(text string) bool {
	mut token := ''
	for ch in (text + ' ').bytes() {
		if word_char(ch) {
			token += ch.ascii_str()
			continue
		}
		name := if token.starts_with('_') { token[1..] } else { token }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup'] || name.starts_with('new_array') {
			return true
		}
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
			begin := if prefix.ends_with('@[typedef]') {
				prefix.len - '@[typedef]'.len
			} else {
				position
			}
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
	if !implementations_only {
		generate_module(source, output, arch, defines)!
		return
	}
	work := work_dir('', 'vinix-header-implementations-')!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	isolated := os.join_path(work, 'headercore')
	os.mkdir(isolated)!
	for name in ['primitive.v', 'policy.v'] {
		os.cp(os.join_path(source, name), os.join_path(isolated, name))!
	}
	mut declarations := []string{}
	common := os.read_file(os.join_path(source, 'common.v'))!
	for name in ['spinlock_t', 'task_struct'] { declarations << foreign_type(common, name)! }
	declarations << foreign_type(os.read_file(os.join_path(source, 'wait.v'))!, 'atomic_t')!
	os.write_file(os.join_path(isolated, 'native_types.v'), '@[translated]\nmodule headercore\n' +
		'#include "linuxkpi_header_primitive_v_contract.h"\n' + declarations.join('\n') + '\n')!
	generate_module(isolated, output, arch, defines)!
}

pub struct ModuleCommandError {
pub:
	argv   []string
	result Result
}

pub fn (failure ModuleCommandError) msg() string {
	return failure.result.stdout + failure.result.stderr
}

pub fn (failure ModuleCommandError) code() int { return 0 }

pub fn generate_module(source string, output string, arch string, defines []string) ! {
	result := generate_module_capture(source, output, arch, defines)!
	print(result.stdout)
	eprint(result.stderr)
}

pub fn generate_module_capture(source string, output string, arch string, defines []string) !Result {
	selected := command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
		root()], '', -1, os.environ())!.stdout
	work := work_dir('', 'vinix-v-module-')!
	defer { module_remove_tree(work) or { eprintln(err) } }
	name := module_name(source)
	if source.contains('\x00') || output.contains('\x00') || arch.contains('\x00') || defines.any(it.contains('\x00')) {
		return error('embedded null byte')
	}
	state := os.stat(source) or { return ModuleFileError{source, err.code(), err.msg()} }
	if state.get_filetype() != .directory {
		return ModuleFileError{source, 20, 'Invalid source directory'}
	}
	module_copy(source, module_join(work, name))!
	mut imported_abiargs := false
	for path in module_paths(source)! {
		for line in module_read(path)!.split('\n') {
			trimmed := module_trim(line)
			if trimmed.starts_with('import abiargs') {
				tail := trimmed['import abiargs'.len..]
				if tail == '' || module_space(tail.runes()[0]) { imported_abiargs = true }
			}
		}
	}
	if imported_abiargs {
		module_copy(module_join(root(), 'kernel/abiargs'), module_join(work, 'abiargs'))!
	}
	os.write_file(os.join_path(work, 'v.mod'), "Module { name: 'native_module' }\n")!
	os.write_file(os.join_path(work, 'entry.v'), 'module main\nimport ${name} as _\n')!
	mut argv := [selected, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', arch,
		'-target-libc-headers', '-gc', 'none', '-manualfree']
	for define in defines { argv << ['-d', define] }
	argv << ['-o', output, work]
	mut env := os.environ()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	compiled := capture(argv, '', -1, env)!
	if compiled.code != 0 { return ModuleCommandError{argv, compiled} }
	mut text := scalar_metadata(source, module_read(output)!)!
	for symbol in ['_vinit', '_vcleanup', '_vinit_caller', '_vcleanup_caller', '_vno_main_init_caller',
		'_v3_no_main_initialized'] {
		text = module_replace(text, symbol, name + '_' + symbol, false)
	}
	if imported_abiargs { text = module_replace(text, 'abiargs__', name + '__abiargs__', true) }
	if text.split('\n').any(it.contains('visibility("default"))) ') && it.all_after('visibility("default"))) ').contains(' backtrace(') && !it.all_after('visibility("default"))) ').all_before(' backtrace(').contains(';')) {
		text = '#define __V_HAVE_EXECINFO_H 1\n' + text
	}
	module_write(output, text)!
	return compiled
}

fn readonly_metadata(source string, marker string) !map[string][]string {
	mut result := map[string][]string{}
	mut paths := module_paths(source)!
	paths.sort()
	for path in paths {
		for line in module_read(path)!.split('\n') {
			if !line.starts_with(marker) { continue }
			value := module_trim_right(line[marker.len..])
			pieces := value.split('.')
			if pieces.len == 2 && pieces.all(module_identifier(it)) {
				mut parameters := result[pieces[0]]
				if pieces[1] !in parameters { parameters << pieces[1] }
				result[pieces[0]] = parameters
			}
		}
	}
	return result
}

fn readonly_parameters(raw string, parameter string, pointer bool) !string {
	runes := raw.runes()
	needle := ((if pointer { '** ' } else { '* ' }) + parameter).runes()
	mut result := ''
	mut index := 0
	mut count := 0
	for index < runes.len {
		if module_word(runes[index]) && (index == 0 || !module_word(runes[index - 1])) {
			mut end := index
			for end < runes.len && module_word(runes[end]) { end++ }
			stop := end + needle.len
			if stop <= runes.len && runes[end..stop] == needle && (stop == runes.len || runes[stop] == `,`) {
				typ := runes[index..end].string()
				result += (if pointer { typ + '* const* ' } else { 'const ' + typ + '* ' }) + parameter
				index = stop
				count++
				continue
			}
		}
		result += runes[index].str()
		index++
	}
	if count != 1 {
		return error('Readonly metadata does not match exported parameter ' + parameter)
	}
	return result
}

fn module_prototypes(text string) []string {
	marker := '__attribute__((visibility("default"))) '
	mut remaining := text
	mut result := []string{}
	for remaining.contains(marker) {
		remaining = remaining.all_after(marker)
		end := remaining.index(';') or { continue }
		prototype := remaining[..end]
		if prototype != '' && !prototype.contains('{') && !prototype.contains('}') && !prototype.contains('\n') {
			result << prototype
			remaining = remaining[end + 1..]
		}
	}
	return result
}

fn module_signature(prototype string) !(string, string, string) {
	if !prototype.ends_with(')') { return error('Unsupported exported declaration: ' + prototype) }
	runes := prototype.runes()
	for index, ch in runes {
		if index == 0 || ch != ` ` { continue }
		mut end := index + 1
		for end < runes.len && module_word(runes[end]) { end++ }
		if end > index + 1 && end < runes.len && runes[end] == `(` {
			return runes[..index].string(), runes[index + 1..end].string(), runes[end + 1..runes.len - 1].string()
		}
	}
	return error('Unsupported exported declaration: ' + prototype)
}

pub fn emit_module_header(source string, output string, header string) ! {
	mut readonly := readonly_metadata(source, '// ABI readonly: ')!
	mut readonly_pointer := readonly_metadata(source, '// ABI readonly-pointer: ')!
	mut declarations := []string{}
	for prototype in module_prototypes(module_read(output)!) {
		result, name, raw_parameters := module_signature(prototype)!
		mut parameters := raw_parameters
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
		for vtype, ctype in {
			'i32':   'int32_t'
			'u32':   'uint32_t'
			'i64':   'int64_t'
			'u64':   'uint64_t'
			'i16':   'int16_t'
			'u16':   'uint16_t'
			'i8':    'int8_t'
			'u8':    'uint8_t'
			'usize': 'size_t'
			'isize': 'intptr_t'
		} {
			declaration = module_replace(declaration, vtype, ctype, false)
		}
		name_start := declaration.index(name) or { return error('substring not found') }
		mut types := [module_trim(declaration[..name_start])]
		parameter_text := declaration.all_after('(').all_before_last(');')
		for parameter in parameter_text.split(',') { types << module_parameter_type(parameter) }
		mut allowed := ['void', 'bool', 'char', 'short', 'int', 'long', 'float', 'double', 'const',
			'signed', 'unsigned', 'size_t', 'intptr_t']
		for prefix in ['', 'u'] {
			for bits in [8, 16, 32, 64] { allowed << '${prefix}int${bits}_t' }
		}
		mut unknown := []string{}
		for typ in types {
			for token in module_word_tokens(typ) {
				if token !in allowed && token !in unknown { unknown << token }
			}
		}
		unknown.sort()
		if unknown.len > 0 {
			return error('Export ${name} requires unsupported public types: ${unknown}')
		}
		declarations << declaration
	}
	if readonly.len > 0 || readonly_pointer.len > 0 {
		return error('Readonly metadata names absent exports: ${module_metadata_repr(readonly)}, ${module_metadata_repr(readonly_pointer)}')
	}
	if declarations.len == 0 { return error('Module has no exported declarations') }
	mut guard := 'VINIX_GENERATED_'
	for ch in module_upper(module_name(header)).runes() {
		guard += if module_word(ch) { ch.str() } else { '_' }
	}
	module_write(header, '// Generated from V; do not maintain this build artifact.\n' +
		'#ifndef ${guard}\n#define ${guard}\n' + '#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n' +
		'#ifdef __cplusplus\nextern "C" {\n#endif\n' + declarations.join('\n') +
		'\n#ifdef __cplusplus\n}\n#endif\n#endif\n')!
}
