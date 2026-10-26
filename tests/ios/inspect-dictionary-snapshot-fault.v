// SPDX-License-Identifier: GPL-2.0-or-later
// Independently map the dictionary checkpoint's null read to the Mach-O image.
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
	vmaddr := field(mapping, 'vmaddr')!
	pc := field(fault, 'pc')!
	lr := field(registers, 'x30')!
	if pc < base || pc - base >= field(mapping, 'size')! { return error('fault outside main image') }
	if lr < base || lr - base >= field(mapping, 'size')! { return error('LR outside main image') }
	image_pc := pc - base + vmaddr
	image_lr := lr - base + vmaddr
	if image_pc != 0x1006b2900 || image_lr != 0x1006b2e5c { return error('unexpected checkpoint fault') }
	if field(fault, 'signal')! != 11 || field(fault, 'code')! != 1
		|| field(fault, 'address')! != 0 || field(fault, 'fault_address')! != 0
		|| field(registers, 'x08')! != 0 { return error('unexpected null read context') }
	code := offset(image, image_pc - 8, 12)!
	if image.data[code..code + 12].hex() != '68d03bd508f17d92080140f9' { return error('unexpected fault instructions') }
	lines := [mapping, fault, registers,
		'FAULT-MAP: runtime_pc=0x${pc.hex()} image_pc=0x${image_pc.hex()} image_lr=0x${image_lr.hex()}',
		'FAULT-CODE: mrs x8, TPIDRRO_EL0; and x8, x8, #0xfffffffffffffff8; ldr x8, [x8]',
		'The image reads Darwin thread data directly. The masked register value is zero at the fault; Linux TPIDRRO_EL0 is not a Darwin pthread pointer. Application startup remains incomplete.']
	result := os.exec(['/opt/homebrew/opt/llvm/bin/llvm-objdump', '--disassemble', '--no-show-raw-insn',
		'--start-address=0x1006b28dc', '--stop-address=0x1006b2948', application])
	if result.exit_code != 0 { return error(result.output) }
	os.write_file(out + '/fault-analysis.txt', lines.join('\n') + '\n')!
	os.write_file(out + '/fault-disassembly.txt', result.output)!
	println(lines.join('\n'))
}

fn main() {
	if os.args.len != 4 { eprintln('usage: inspect-dictionary-snapshot-fault APPLICATION SERIAL OUTPUT'); exit(2) }
	out := os.real_path(os.args[3])
	root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('output must exist outside repository'); exit(2) }
	inspect(os.args[1], os.args[2], out) or { eprintln(err); exit(1) }
}
