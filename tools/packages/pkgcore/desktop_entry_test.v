// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import strings

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

// Keep the checks active in production builds as well as ordinary V tests.
fn desktop_entry_require(condition bool, reason string) {
	if !condition { panic(reason) }
}

// Read one XDG string independently of the package serializer. Boundary
// whitespace is removed before interpreting the standard string escapes.
fn desktop_entry_read_value(text string, key string) !string {
	prefix := key + '='
	defer { unsafe { prefix.free() } }
	lines := text.split_into_lines()
	defer { unsafe { lines.free() } }
	for line in lines {
		if !line.starts_with(prefix) { continue }
		mut offset := prefix.len
		for offset < line.len && line[offset] in [` `, `\t`, `\r`] { offset++ }
		mut end := line.len
		for end > offset && line[end - 1] in [` `, `\t`, `\r`] { end-- }
		mut value := strings.new_builder(end - offset)
		defer { unsafe { value.free() } }
		for offset < end {
			if line[offset] != `\\` { value.write_u8(line[offset]); offset++; continue }
			offset++
			if offset == end { return error('unterminated XDG escape') }
			match line[offset] {
				`s` { value.write_u8(` `) }
				`n` { value.write_u8(`\n`) }
				`t` { value.write_u8(`\t`) }
				`r` { value.write_u8(`\r`) }
				`\\` { value.write_u8(`\\`) }
				else { return error('unknown XDG escape') }
			}
			offset++
		}
		return value.str()
	}
	return error('missing XDG key')
}

struct DesktopEntryCase {
	name string
	description string
	encoded_name string
	encoded_description string
}

fn test_desktop_entry_preserves_signed_strings_for_xdg_readers() {
	for sample in [
		DesktopEntryCase{ name: 'Editor é🚀', description: 'Write ordinary text; safely',
			encoded_name: 'Editor é🚀', encoded_description: 'Write ordinary text; safely' },
		DesktopEntryCase{ name: 'Path\\name\\tab\\rules\\space\\\\end\\', description: '\\n \\t \\r \\s \\; \\x',
			encoded_name: 'Path\\\\name\\\\tab\\\\rules\\\\space\\\\\\\\end\\\\', encoded_description: '\\\\n \\\\t \\\\r \\\\s \\\\; \\\\x' },
		DesktopEntryCase{ name: '  Editor = é🚀  ', description: ' \\s literal escape \\n ',
			encoded_name: '\\s\\sEditor = é🚀\\s\\s', encoded_description: '\\s\\\\s literal escape \\\\n\\s' },
		DesktopEntryCase{ name: ' ', description: '   ', encoded_name: '\\s', encoded_description: '\\s\\s\\s' },
		DesktopEntryCase{ name: 'Empty comment', description: '', encoded_name: 'Empty comment', encoded_description: '' },
	] {
		p := Package{ id: 'app', name: sample.name, description: sample.description, architecture: 'aarch64',
			version: '1.0.0', kind: 'native', license: 'MIT', entrypoint: 'bin/app', associations: ['text/plain', 'text/markdown'],
			files: [Payload{ path: 'bin/app', sha256: 'a'.repeat(64), executable: true }] }
		p.validate() or { panic(err) }
		entry := desktop_entry(p)
		expected := '[Desktop Entry]\nType=Application\nName=' + sample.encoded_name + '\nComment=' + sample.encoded_description
			+ '\nExec=/usr/bin/vinix-package run app %F\nTerminal=false\nMimeType=text/plain;text/markdown;\nX-Vinix-Package=app\nX-Vinix-Runtime=\n'
		desktop_entry_require(entry == expected, 'XDG Name/Comment bytes differ from canonical string encoding')
		name := desktop_entry_read_value(entry, 'Name') or { panic(err) }
		comment := desktop_entry_read_value(entry, 'Comment') or { panic(err) }
		defer { unsafe { entry.free(); expected.free(); name.free(); comment.free() } }
		desktop_entry_require(name == sample.name && comment == sample.description, 'XDG decoding changed signed metadata')
		desktop_entry_require(p.name == sample.name && p.description == sample.description, 'launcher changed the manifest')
	}
	// Actual controls remain refused by signed-manifest admission. Literal escape
	// sequences above are printable metadata and must remain literal after reading.
	for control in ['\n', '\r', '\t', '\x00', '\x7f'] {
		for field in ['name', 'description'] {
			p := Package{ id: 'app', name: if field == 'name' { 'Editor' + control } else { 'Editor' },
				description: if field == 'description' { 'Text' + control } else { 'Text' }, architecture: 'aarch64',
				version: '1.0.0', kind: 'native', license: 'MIT', entrypoint: 'bin/app',
				files: [Payload{ path: 'bin/app', sha256: 'a'.repeat(64), executable: true }] }
			mut refused := false
			p.validate() or { refused = true }
			desktop_entry_require(refused, 'manifest admission accepted a control character')
		}
	}
	println('XDG STRING exact bytes, literal escapes, boundary spaces, UTF-8, empty comment and manifest control refusal PASS')
}

fn test_desktop_entry_escaped_string_assembly_retires_owned_scratch() {
	$if track_heap ? {
		p := Package{ id: 'app', name: '  \\n\\t\\r\\s\\\\é  ', description: ' literal \\escape ',
			architecture: 'aarch64', version: '1.0.0', kind: 'native', license: 'MIT', entrypoint: 'bin/app' }
		// Warm the path before measuring ownership of each independent result.
		warm := desktop_entry(p); unsafe { warm.free() }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { text := desktop_entry(p); unsafe { text.free() } }
		kept := C.vinix_heap_end()
		desktop_entry_require(kept == 0 && C.vinix_heap_count() == 0, 'escaped launcher assembly retained owned scratch')
		println('XDG STRING 1000 escaped launcher assemblies retain zero tracked bytes/records PASS')
	}
}
