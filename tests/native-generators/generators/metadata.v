// SPDX-License-Identifier: GPL-2.0-or-later
module generators

import hosttest
import os

pub const metadata_fields = ['next', 'info_version', 'id', 'name', 'version', 'reference_count',
	'reference_list', 'address', 'size', 'hdr_size', 'start', 'stop']
pub const metadata_offsets = [0, 8, 12, 16, 80, 144, 148, 156, 164, 172, 180, 188]

struct Cursor {
mut:
	text string
}

fn (mut cursor Cursor) take_until(delimiter string) !string {
	end := cursor.text.index(delimiter) or { return error('unsupported metadata initializer') }
	value := cursor.text[..end].clone()
	cursor.text = cursor.text[end + delimiter.len..].clone()
	return value
}

// Promote the compiler's sole aggregate and its two literal fixed-array
// copies. Any remaining constructor work must fail before native loading.
pub fn static_metadata(raw string) !string {
	body := hosttest.extract_body(raw, 'kmodmeta__vinit')!
	mut rest := Cursor{body.all_after('\n').all_before_last('\n}').trim_space()}
	prefix := 'kmod_info = ({kmodmeta__Info '
	if !rest.text.starts_with(prefix) {
		return error('V metadata initializer is not the expected fixed aggregate')
	}
	rest.text = rest.text[prefix.len..].clone()
	temporary := rest.take_until(' = (kmodmeta__Info)')!
	if temporary == '' || !temporary.bytes().all(hosttest.word_char(it)) || temporary[0].is_digit() {
		return error('unsupported aggregate temporary')
	}
	if !rest.text.starts_with('{') { return error('unsupported metadata aggregate') }
	mut initializer := rest.take_until('}; ')! + '}'
	if initializer[1..].contains('{') { return error('unsupported nested metadata aggregate') }
	for field in ['name', 'version'] {
		copy_prefix := 'memcpy(' + temporary + '.' + field + ', (u8[64])'
		if !rest.text.starts_with(copy_prefix) {
			return error('unsupported fixed ' + field + ' initializer')
		}
		rest.text = rest.text[copy_prefix.len..].clone()
		array := rest.take_until(', sizeof(' + temporary + '.' + field + '));')!
		if !array.starts_with('{') || !array.ends_with('}') || array[1..array.len - 1].contains('{') || array[1..array.len - 1].contains('}') {
			return error('unsupported fixed array literal')
		}
		initializer = initializer[..initializer.len - 1] + ', .' + field + ' = ' + array + '}'
		if rest.text.starts_with(' ') { rest.text = rest.text[1..].clone() }
	}
	if rest.text != temporary + ';});' {
		return error('kmod metadata cannot call a runtime initializer')
	}
	mut token := ''
	for ch in initializer.bytes() {
		if hosttest.word_char(ch) {
			token += ch.ascii_str()
			continue
		}
		if ch == `(` && token != '' && token != 'u8' {
			return error('kmod metadata cannot call a runtime initializer')
		}
		if !ch.is_space() { token = '' }
	}
	start := raw.index('typedef struct kmodmeta__Info kmodmeta__Info;') or { return error('missing metadata declaration') }
	end := start + (raw[start..].index('\nstatic void v3_eprint_lit') or { return error('missing metadata declaration boundary') })
	declarations := raw[start..end].split('\n').filter(!(it.starts_with('typedef struct __v_option ') || it.starts_with('typedef struct __v_result '))).join('\n')
	aliases := raw.split('\n').filter(it in ['typedef uint8_t u8;', 'typedef int32_t i32;',
		'typedef uint32_t u32;'])
	if aliases.len != 3 { return error('unsupported metadata integer declarations') }
	mut result := '// Generated from V; do not maintain this build artifact.\n#include <stddef.h>\n#include <stdint.h>\n' + aliases.join('\n') + '\n' + declarations +
		'\n__attribute__((visibility("default"))) kmodmeta__Info kmod_info = ' + initializer + ';\n' +
		'_Static_assert(sizeof(kmodmeta__Info) == 196, "kmod size");\n_Static_assert(_Alignof(kmodmeta__Info) == 4, "kmod alignment");\n'
	for index, field in metadata_fields {
		result += '_Static_assert(offsetof(kmodmeta__Info, ' + field + ') == ' + metadata_offsets[index].str() + ', "kmod ' + field + '");\n'
	}
	return result
}

pub fn generate_metadata(output string, arch string) ! {
	work := hosttest.work_dir('', 'vinix-kmod-meta-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	raw := work + '/metadata.c'
	generate_module(root() + '/tests/alloc-bench/kmodmeta', raw, arch, ['nofloat'])!
	os.write_file(output, static_metadata(os.read_file(raw)!)!)!
}
