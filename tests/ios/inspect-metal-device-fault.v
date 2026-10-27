// SPDX-License-Identifier: GPL-2.0-or-later
// Verify the Metal import and its nil branch, then record the observed next stop.
module main

import macho
import os
import strconv

fn field(line string, name string) !u64 {
	if !line.contains(name + '=0x') { return error('missing ' + name) }
	return strconv.parse_uint(line.all_after(name + '=0x').all_before(' ').trim_space(), 16, 64)
}

fn offset(image macho.Image, address u64, size u64) !int {
	for segment in image.segments {
		if address >= segment.address && address - segment.address < segment.filesize
			&& size <= segment.filesize - (address - segment.address) {
			return int(segment.fileoff + address - segment.address)
		}
	}
	return error('address outside file-backed image')
}

fn word(image macho.Image, address u64) !u32 {
	start := offset(image, address, 4)!
	mut value := u32(0)
	for i in 0 .. 4 { value |= u32(image.data[start + i]) << (i * 8) }
	return value
}

fn branch(image macho.Image, address u64, link bool) !u64 {
	instruction := word(image, address)!
	if instruction >> 26 != u32(if link { 0x25 } else { 0x05 }) { return error('unexpected branch opcode') }
	mut displacement := i64(instruction & 0x03ffffff) * 4
	if instruction & 0x02000000 != 0 { displacement -= i64(1) << 28 }
	return u64(i64(address) + displacement)
}

fn inspect(application string, serial string, out string) ! {
	image := macho.parse(os.read_bytes(application)!)!
	log := os.read_file(serial)!.replace('\r\n', '\n')
	mappings := log.split_into_lines().filter(it.starts_with('iOS probe image:') && it.ends_with('/FortniteClient-IOS-Shipping'))
	if mappings.len != 1 || field(mappings[0], 'base')! == 0
		|| field(mappings[0], 'vmaddr')! != 0x100000000
		|| field(mappings[0], 'size')! != 0x15598000 { return error('unexpected application mapping') }
	application_log := log.all_after('iOS startup: application entry')
	stop := 'V panic: iOS: unimplemented Objective-C method NSNotificationCenter addObserverForName:object:queue:usingBlock:'
	if log.count('iOS startup: application entry') != 1 || application_log.count(stop + '\n') != 1
		|| log.count('V panic:') != 1 || application_log.contains('IOS-PROBE-FAULT:')
		|| application_log.contains('IOS-PROBE-REGS:')
		|| application_log.count('FORTNITE PROBE: process exit status 1\n') != 1 {
		return error('unexpected application stop')
	}
	call := u64(0x100629528)
	veneer := branch(image, call, true)!
	stub := branch(image, veneer, false)!
	if veneer != 0x107c28630 || stub != 0x10c63cf0c
		|| word(image, stub)! != 0xb000b2f0 || word(image, stub + 4)! != 0xf947ba10
		|| word(image, stub + 8)! != 0xd61f0200 { return error('unexpected Metal call path') }
	// Decode CBZ X0's signed immediate independently of objdump.
	nil_check := call + 8
	instruction := word(image, nil_check)!
	if instruction & 0xff00001f != 0xb4000000 { return error('missing nil-device branch') }
	mut displacement := i64((instruction >> 5) & 0x7ffff) * 4
	if instruction & 0x00800000 != 0 { displacement -= i64(1) << 21 }
	nil_target := u64(i64(nil_check) + displacement)
	if nil_target != 0x100629660 { return error('changed nil-device target') }
	imports := image.imported_symbols()!.filter(it.name == '_MTLCreateSystemDefaultDevice')
	if imports.len != 1 || !imports[0].weak
		|| imports[0].library != '/System/Library/Frameworks/Metal.framework/Metal' {
		return error('unexpected Metal import')
	}
	indirect := os.exec(['/opt/homebrew/opt/llvm/bin/llvm-objdump', '--macho', '--indirect-symbols', application])
	if indirect.exit_code != 0 { return error(indirect.output) }
	mut selected := []string{}
	for address in ['0x000000010c63cf0c', '0x000000010dc99f70'] {
		matches := indirect.output.split_into_lines().filter(it.starts_with(address + ' '))
		if matches.len != 1 || !matches[0].ends_with(' _MTLCreateSystemDefaultDevice') {
			return error('unexpected indirect symbol at ' + address)
		}
		selected << matches[0]
	}
	mut disassembly := ''
	for bounds in [['0x100629520', '0x100629548']!, ['0x100629660', '0x100629674']!,
		['0x107c28630', '0x107c28634']!, ['0x10c63cf0c', '0x10c63cf18']!] {
		result := os.exec(['/opt/homebrew/opt/llvm/bin/llvm-objdump', '--disassemble', '--no-show-raw-insn',
			'--start-address=' + bounds[0], '--stop-address=' + bounds[1], application])
		if result.exit_code != 0 { return error(result.output) }
		disassembly += result.output
	}
	lines := [mappings[0], stop,
		'METAL-CALL: call=0x${call.hex()} veneer=0x${veneer.hex()} stub=0x${stub.hex()}',
		'METAL-IMPORT: _MTLCreateSystemDefaultDevice weak=true library=' + imports[0].library,
		'METAL-NIL-BRANCH: cbz x0 at 0x${nil_check.hex()} target=0x${nil_target.hex()}',
		'The import resolves and startup reaches the notification observer method without an application signal fault. Static code checks verify the nil branch; no GPU device or game frame is verified.']
	os.write_file(out + '/fault-analysis.txt', lines.join('\n') + '\n')!
	os.write_file(out + '/fault-disassembly.txt', disassembly)!
	os.write_file(out + '/fault-indirect-symbols.txt', selected.join('\n') + '\n')!
	println(lines.join('\n'))
}

fn main() {
	if os.args.len != 4 { eprintln('usage: inspect-metal-device-fault APPLICATION SERIAL OUTPUT'); exit(2) }
	out := os.real_path(os.args[3])
	root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('output must exist outside repository'); exit(2) }
	inspect(os.args[1], os.args[2], out) or { eprintln(err); exit(1) }
}
