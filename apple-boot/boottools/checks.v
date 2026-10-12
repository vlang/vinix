// SPDX-License-Identifier: GPL-2.0-or-later
module boottools

import cachecli
import hosttest
import os
import sourcecommand

pub struct Comparison {
pub:
	matched  int
	skipped  int
	failures []string
}

pub fn check_tree(tree Tree, windows map[string][]Range, bootargs string) Comparison {
	mut failures := []string{}
	if 'vinix,apple-adt' !in tree.nodes[tree.root].properties {
		failures << 'the root does not mark the tree as a converted ADT'
	}
	mut chosen_ok := false
	for index in tree.nodes[tree.root].children {
		if tree.nodes[index].name == 'chosen' {
			chosen_ok = tree.nodes[index].properties['bootargs'] == (bootargs + '\x00').bytes()
			break
		}
	}
	if !chosen_ok { failures << '/chosen/bootargs is missing or wrong' }
	mut seen := map[string]bool{}
	mut matched := 0
	mut skipped := 0
	for index, _ in tree.nodes {
		path := tree.path(index)
		expected := windows[path] or { continue }
		if expected.len == 0 || path in seen { continue }
		seen[path] = true
		actual := tree.translated_reg(index)
		if !actual.supported {
			skipped++
			continue
		}
		if actual.ranges.len < expected.len || actual.ranges[..expected.len].map(it.address) != expected.map(it.address) {
			failures << path + ': ' + addresses(actual.ranges) + ' != ' + addresses(expected)
		} else {
			matched++
		}
	}
	return Comparison{matched, skipped, failures}
}

fn addresses(ranges []Range) string {
	return '[' + ranges.map("'0x" + it.address.hex() + "'").join(', ') + ']'
}

pub fn converter_cli(argv []string) int {
	$if !macos {
		println("SKIP: needs macOS's IORegistry")
		return 0
	}
	args := cachecli.arguments(argv, ['--converter', '--ioreg-plist'], []string{}, []string{}, 0, 0, 'usage: check_converter [--converter EXECUTABLE --ioreg-plist FILE]') or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	return converter_options(args) or {
		eprintln(err)
		if cachecli.cancelled() { return cachecli.interrupt_status() }
		return 1
	}
}

fn converter_options(args cachecli.Arguments) !int {
	converter := path_option(args, '--converter', here() + '/build/adt2fdt')
	if '--converter' !in args.options { command(['make', '-C', here(), '-s', 'build/adt2fdt'])! }
	adt := if '--ioreg-plist' in args.options {
		adt_from_plist(os.read_bytes(args.value('--ioreg-plist', ''))!, false)!
	} else {
		ioreg(false)!
	}
	work := sourcecommand.temporary('vinix-apple-converter')!
	defer { os.rmdir_all(work) or {} }
	os.write_file_array(work + '/adt.bin', adt.data)!
	bootargs := 'vinix.converter_check=1'
	result := sourcecommand.capture([converter, work + '/adt.bin', work + '/fdt.dtb', bootargs], os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error('converter failed: ' + result.stderr) }
	comparison := check_tree(parse_fdt(os.read_bytes(work + '/fdt.dtb')!)!, adt.memory, bootargs)
	for failure in comparison.failures { println('FAIL: ' + failure) }
	println(comparison.matched.str() + " nodes match XNU's register windows, " + comparison.skipped.str() + ' skipped, ' + comparison.failures.len.str() + ' failures')
	return if comparison.failures.len > 0 { 1 } else { 0 }
}

pub fn ioreg_cli(argv []string) int {
	args := cachecli.arguments(argv, ['--ioreg-plist'], []string{}, []string{}, 1, 1, 'usage: ioreg_adt OUTPUT [--ioreg-plist FILE]') or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	return ioreg_options(args) or {
		eprintln(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
}

fn ioreg_options(args cachecli.Arguments) !int {
	adt := if '--ioreg-plist' in args.options {
		adt_from_plist(os.read_bytes(path_option(args, '--ioreg-plist', ''))!, false)!
	} else {
		ioreg(false)!
	}
	os.write_file_array(path_value(args.positional[0]), adt.data)!
	println(adt.data.len.str() + ' bytes, ' + adt.memory.len.str() + ' nodes with IODeviceMemory')
	return 0
}

pub fn abi_source(text string) !(string, int) {
	begin := text.index('typedef struct applecore__') or { return error('missing generated Apple storage declarations') }
	end := begin + (text[begin..].index('\nstatic void v3_eprint_lit') or { return error('missing generated storage boundary') })
	mut source := '#include <stddef.h>\n#include <stdint.h>\n#include <stdbool.h>\ntypedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64; typedef int32_t i32;\n'
	// Compiler-emitted storage has no nested bodies. Select the same typedef
	// and structure declarations as the original check, excluding enums/code.
	mut offset := begin
	for offset < end {
		tail := text[offset..end]
		typedef_at := tail.index('typedef ') or { tail.len }
		struct_at := tail.index('struct ') or { tail.len }
		start := if typedef_at < struct_at { typedef_at } else { struct_at }
		if start == tail.len { break }
		statement := tail[start..]
		semicolon := statement.index(';') or { return error('unterminated generated declaration') }
		mut stop := semicolon + 1
		if brace := statement.index('{') {
			if brace < semicolon {
				close := statement.index('}') or { return error('unterminated generated structure') }
				stop = close + 1 + (statement[close + 1..].index(';') or { return error('unterminated generated structure') }) + 1
			} else if !statement.starts_with('typedef ') {
				offset += start + stop
				continue
			}
		} else if !statement.starts_with('typedef ') {
			offset += start + stop
			continue
		}
		source += statement[..stop] + '\n'
		offset += start + stop
	}
	source += '#include "adt.h"\n#include "fdt.h"\n#include "loader.h"\n'
	mut checked := 0
	for name in ['adt', 'adt_property', 'fdt_builder', 'adt_fdt_extras', 'boot_video', 'boot_info',
		'payload_header', 'allocator', 'pagemap', 'loaded_kernel', 'memmap_entry', 'memmap',
		'reserved_range', 'reserved_set', 'limine_inputs'] {
		vname := 'applecore__' + name[..1].to_upper() + name[1..]
		record := hosttest.record(text, vname) or { continue }
		source += '_Static_assert(sizeof(' + vname + ') == sizeof(struct ' + name + '), "' + name + ' size");\n'
		source += '_Static_assert(_Alignof(' + vname + ') == _Alignof(struct ' + name + '), "' + name + ' alignment");\n'
		for line in record.all_after('{').all_before_last('}').split_into_lines() {
			if !line.contains(';') { continue }
			declaration := line.all_before(';').all_before('[').trim_space()
			mut start := declaration.len
			for start > 0 && hosttest.word_char(declaration[start - 1]) { start-- }
			field := declaration[start..]
			if field.len == 0 { continue }
			cfield := if field == 'type_' { 'type' } else { field }
			source += '_Static_assert(offsetof(' + vname + ', ' + field + ') == offsetof(struct ' + name + ', ' + cfield + '), "' + name + '.' + cfield + '");\n'
			checked++
		}
	}
	if checked == 0 { return error('no Apple structure fields checked') }
	return source, checked
}

pub fn check_abi(source_path string, work string) ! {
	source, checked := abi_source(os.read_file(source_path)!)!
	output := work + '/abi.c'
	os.write_file(output, source)!
	command([os.getenv_opt('CC') or { 'clang' }, '-std=gnu11', '-ffreestanding', '-fno-builtin',
		'-fsyntax-only', '-I' + here() + '/src', output])!
	println('Apple loader: C/V structure ABI matched (' + checked.str() + ' fields)')
}

pub fn abi_cli(argv []string) int {
	args := cachecli.arguments(argv, ['--source'], []string{}, []string{}, 0, 0, 'usage: check-v-abi [--source GENERATED_C]') or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	abi_options(args) or {
		eprintln(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
	return 0
}

fn abi_options(args cachecli.Arguments) ! {
	work := sourcecommand.temporary('vinix-apple-abi')!
	defer { os.rmdir_all(work) or {} }
	source := path_option(args, '--source', work + '/core.c')
	if '--source' !in args.options { command([here() + '/compile-v', '--host', source])! }
	check_abi(source, work)!
}
