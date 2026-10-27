// SPDX-License-Identifier: GPL-2.0-or-later
// Map the locale checkpoint's null branch through both veneers to its Metal import.
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
	mut mapping := ''
	mut fault := ''
	mut registers := ''
	for line in log.split_into_lines() {
		if line.starts_with('iOS probe image:') && line.ends_with('/FortniteClient-IOS-Shipping') { mapping = line }
		if line.starts_with('IOS-PROBE-FAULT: signal=') { fault = line }
		if line.starts_with('IOS-PROBE-REGS:') { registers = line }
	}
	base := field(mapping, 'base')!
	lr := field(registers, 'x30')!
	if lr < base || lr - base >= field(mapping, 'size')! { return error('LR outside main image') }
	image_lr := lr - base + field(mapping, 'vmaddr')!
	if image_lr != 0x10062952c || field(fault, 'pc')! != 0
		|| field(fault, 'signal')! != 11 || field(fault, 'code')! != 1
		|| field(fault, 'address')! != 0 || field(fault, 'fault_address')! != 0
		|| field(registers, 'x16')! != 0 || registers.count(' x') != 31 {
		return error('unexpected null branch context')
	}
	veneer := branch(image, image_lr - 4, true)!
	stub := branch(image, veneer, false)!
	if veneer != 0x107c28630 || stub != 0x10c63cf0c
		|| word(image, stub)! != 0xb000b2f0 || word(image, stub + 4)! != 0xf947ba10
		|| word(image, stub + 8)! != 0xd61f0200 { return error('unexpected Metal call path') }
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
	for bounds in [['0x1006294f0', '0x100629560']!, ['0x107c28630', '0x107c28634']!, ['0x10c63cf0c', '0x10c63cf18']!] {
		result := os.exec(['/opt/homebrew/opt/llvm/bin/llvm-objdump', '--disassemble', '--no-show-raw-insn',
			'--start-address=' + bounds[0], '--stop-address=' + bounds[1], application])
		if result.exit_code != 0 { return error(result.output) }
		disassembly += result.output
	}
	lines := [mapping, fault, registers,
		'FAULT-MAP: image_lr=0x${image_lr.hex()} call=0x${(image_lr - 4).hex()} veneer=0x${veneer.hex()} stub=0x${stub.hex()}',
		'FAULT-IMPORT: _MTLCreateSystemDefaultDevice weak=true library=' + imports[0].library,
		'FAULT-CODE: adrp x16, 0x10dc99000; ldr x16, [x16, #0xf70]; br x16',
		'The call reaches the Metal device-creation import with x16=0 and faults at PC=0. No GPU device or game frame is verified.']
	os.write_file(out + '/fault-analysis.txt', lines.join('\n') + '\n')!
	os.write_file(out + '/fault-disassembly.txt', disassembly)!
	os.write_file(out + '/fault-indirect-symbols.txt', selected.join('\n') + '\n')!
	println(lines.join('\n'))
}

fn main() {
	if os.args.len != 4 { eprintln('usage: inspect-locale-preferred-fault APPLICATION SERIAL OUTPUT'); exit(2) }
	out := os.real_path(os.args[3])
	root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('output must exist outside repository'); exit(2) }
	inspect(os.args[1], os.args[2], out) or { eprintln(err); exit(1) }
}
