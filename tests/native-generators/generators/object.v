// SPDX-License-Identifier: GPL-2.0-or-later
module generators

import cachecli
import encoding.utf8
import hosttest
import json2
import os

struct ObjectBytes {
	data []u8
}

fn (blob ObjectBytes) span(offset u64, size u64) ![]u8 {
	if offset > u64(blob.data.len) || size > u64(blob.data.len) - offset {
		return error('truncated Mach-O object')
	}
	return blob.data[int(offset)..int(offset + size)]
}

fn (blob ObjectBytes) number(offset u64, size int) !u64 {
	mut value := u64(0)
	for index, ch in blob.span(offset, u64(size))! { value |= u64(ch) << u32(index * 8) }
	return value
}

struct Section {
	name        string
	size        u64
	offset      u64
	alignment   u64
	relocations u64
	count       u64
}

struct Symbol {
	name        string
	kind        u64
	section     u64
	description u64
	value       u64
}

struct Relocation {
	address u64
	name    string
	info    u64
}

pub struct Descriptor {
pub:
	bytes       string
	relocations []Relocation
	symbols     []Symbol
	alignment   u64
	size        u64
}

// Read object data only. Every count and offset is checked before slicing;
// executable/constructor data and unexpected native symbols are rejected.
pub fn descriptor(data []u8) !Descriptor {
	blob := ObjectBytes{data}
	if blob.number(0, 4)! != 0xfeedfacf || blob.number(12, 4)! != 1 {
		return error('expected 64-bit Mach-O object')
	}
	commands := blob.number(16, 4)!
	limit := u64(32) + blob.number(20, 4)!
	blob.span(32, limit - 32)!
	if commands > (limit - 32) / 8 { return error('invalid load-command count') }
	mut position := u64(32)
	mut sections := []Section{}
	mut symbols_offset := u64(0)
	mut symbols_count := u64(0)
	mut strings_offset := u64(0)
	mut strings_size := u64(0)
	mut have_symbols := false
	for _ in 0 .. int(commands) {
		if position > limit || limit - position < 8 { return error('truncated load command') }
		command := blob.number(position, 4)!
		size := blob.number(position + 4, 4)!
		if size < 8 || size > limit - position { return error('invalid load-command size') }
		if command == 0x19 {
			if size < 72 { return error('truncated segment command') }
			count := blob.number(position + 64, 4)!
			if count > (size - 72) / 80 { return error('invalid section count') }
			for index in 0 .. int(count) {
				start := position + 72 + u64(index) * 80
				sections << Section{blob.span(start, 16)!.bytestr().trim_right('\x00'), blob.number(start + 40, 8)!, blob.number(start + 48, 4)!, blob.number(start + 52, 4)!, blob.number(start + 56, 4)!, blob.number(start + 60, 4)!}
			}
		} else if command == 2 {
			if size < 24 || have_symbols { return error('invalid symbol-table command') }
			have_symbols = true
			symbols_offset = blob.number(position + 8, 4)!
			symbols_count = blob.number(position + 12, 4)!
			strings_offset = blob.number(position + 16, 4)!
			strings_size = blob.number(position + 20, 4)!
		}
		position += size
	}
	if !have_symbols { return error('missing symbol table') }
	blob.span(symbols_offset, symbols_count * 16)!
	strings := blob.span(strings_offset, strings_size)!.bytestr()
	mut names := []string{}
	mut exports := []Symbol{}
	for index in 0 .. int(symbols_count) {
		start := symbols_offset + u64(index) * 16
		string_offset := blob.number(start, 4)!
		if string_offset >= strings_size { return error('invalid symbol string offset') }
		tail := strings[int(string_offset)..]
		end := tail.index('\x00') or { return error('unterminated symbol name') }
		name := tail[..end]
		if !utf8.validate_str(name) { return error('invalid UTF-8 symbol name') }
		names << name
		kind := blob.number(start + 4, 1)!
		if kind & 1 != 0 {
			exports << Symbol{name, kind, blob.number(start + 5, 1)!, blob.number(start + 6, 2)!, blob.number(start + 8, 8)!}
		}
	}
	selected := sections.filter(it.name == '__data')
	if selected.len != 1 { return error('expected one data section') }
	section := selected[0]
	if section.size != 196 || section.alignment != 2 || sections.any(it.name != '__data' && it.size != 0) {
		return error('unexpected descriptor size, alignment or executable data')
	}
	blob.span(section.relocations, section.count * 8)!
	mut relocations := []Relocation{}
	for index in 0 .. int(section.count) {
		start := section.relocations + u64(index) * 8
		info := blob.number(start + 4, 4)!
		symbol := info & 0xffffff
		if info & (1 << 27) == 0 || symbol >= u64(names.len) {
			return error('invalid external relocation')
		}
		relocations << Relocation{blob.number(start, 4)!, names[int(symbol)], info >> 24}
	}
	relocations.sort(a.address < b.address)
	if relocations.len != 2 || relocations[0].address != 180 || relocations[0].name != '_kmod_alloc_start' || relocations[1].address != 188 || relocations[1].name != '_kmod_alloc_stop' {
		return error('unexpected callback relocations')
	}
	exports.sort(a.name < b.name)
	if exports.map(it.name) != ['_kmod_alloc_start', '_kmod_alloc_stop', '_kmod_info'] {
		return error('unexpected external symbols')
	}
	return Descriptor{blob.span(section.offset, section.size)!.hex(), relocations, exports, 4, section.size}
}

fn descriptor_json(record Descriptor) json2.Any {
	return {
		'bytes':       json2.Any(record.bytes)
		'relocations': json2.Any(record.relocations.map(json2.Any([
			json2.Any(it.address),
			json2.Any(it.name),
			json2.Any(it.info),
		])))
		'symbols':     json2.Any(record.symbols.map(json2.Any([json2.Any(it.name), json2.Any(it.kind),
			json2.Any(it.section), json2.Any(it.description), json2.Any(it.value)])))
		'alignment':   json2.Any(record.alignment)
		'size':        json2.Any(record.size)
	}
}

pub fn check_metadata(reference string, state string) ! {
	work := hosttest.work_dir(if state == '' { '.' } else { state }, 'vinix-kmod-check-')!
	mut results := []json2.Any{}
	for arch in ['x86_64', 'arm64'] {
		target := work + '/' + arch
		os.mkdir(target)!
		translated := target + '/v.c'
		original := target + '/c.c'
		generate_metadata(translated, if arch == 'x86_64' { 'amd64' } else { 'arm64' })!
		os.cp(reference, original)!
		mut flags := [os.getenv_opt('CC') or { 'clang' }, '-arch', arch, '-std=c11', '-O2', '-Wall',
			'-Wextra', '-Werror', '-fno-builtin', '-ffreestanding', '-fno-stack-protector']
		flags << if arch == 'x86_64' {
			['-mno-red-zone', '-mno-80387', '-mno-mmx', '-mno-sse', '-mno-sse2']
		} else {
			['-mgeneral-regs-only']
		}
		mut objects := []string{}
		mut commands := []json2.Any{}
		for source in [original, translated] {
			object := hosttest.replace_suffix(source, '.o')
			mut command := flags.clone()
			command << ['-c', source, '-o', object]
			show(checked(command)!)
			commands << json2.Any(hosttest.strings(command))
			objects << object
		}
		c_data := os.read_bytes(objects[0])!
		v_data := os.read_bytes(objects[1])!
		c := descriptor(c_data)!
		v := descriptor(v_data)!
		if c != v { return error(arch + ' descriptor mismatch') }
		results << json2.Any({
			'arch':                   json2.Any(arch)
			'descriptor':             descriptor_json(v)
			'commands':               json2.Any(commands)
			'objects_byte_identical': json2.Any(c_data == v_data)
			'c_sha256':               json2.Any(digest(objects[0])!)
			'v_sha256':               json2.Any(digest(objects[1])!)
		})
	}
	os.write_file(work + '/validation.json', json2.encode(results,
		prettify:      true
		indent_string: '  '
	) + '\n')!
	println('KMOD METADATA: PASS both native ABIs, all196bytes, alignment and callback relocations')
}

pub fn check_cli(argv []string) int {
	args := cachecli.arguments(argv, ['--original-reference', '--state-dir'], []string{}, []string{}, 0, 0, 'usage: test-kmod-info --original-reference FILE --state-dir NEW_DIR') or {
		eprintln(err)
		return 2
	}
	reference := args.required('--original-reference') or {
		eprintln(err)
		return 2
	}
	state := args.required('--state-dir') or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	check_metadata(reference, state) or {
		report_failure(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
	return 0
}
