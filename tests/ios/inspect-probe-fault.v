// SPDX-License-Identifier: GPL-2.0-or-later
// Map the captured Fortnite fault to the unchanged ARM64 Mach-O slice.
module main

import macho
import os
import strconv

fn field(line string, name string) !u64 {
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
		if line.starts_with('IOS-PROBE-FAULT:') { fault = line }
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
	if image_pc != 0x10489b4e4 || image_lr != 0x10489b4ac { return error('unexpected checkpoint fault') }
	code := offset(image, image_pc - 8, 12)!
	if image.data[code..code + 12].hex() != '68008052690f8052090100b9' { return error('unexpected fault instructions') }
	mut lines := [mapping, fault, registers,
		'FAULT-MAP: runtime_pc=0x${pc.hex()} image_pc=0x${image_pc.hex()} image_lr=0x${image_lr.hex()}',
		'FAULT-CODE: mov w8, #3; mov w9, #123; str w9, [x8]']
	for address in [u64(0x10c780456), 0x10c780491, 0x10c78052e] {
		start := offset(image, address, 512)!
		mut end := start
		for end < start + 512 && image.data[end] != 0 { end++ }
		if end == start + 512 { return error('unterminated diagnostic string') }
		lines << 'FAULT-STRING: address=0x${address.hex()} value=' + image.data[start..end].bytestr()
	}
	lines << 'The routine contains an allocation-failure message and deliberately faults. The failed allocation and cause are not established by these registers.'
	os.write_file(out + '/fault-analysis.txt', lines.join('\n') + '\n')!
	result := os.exec(['/opt/homebrew/opt/llvm/bin/llvm-objdump', '--disassemble', '--no-show-raw-insn',
		'--start-address=0x10489b3d8', '--stop-address=0x10489b4e8', application])
	if result.exit_code != 0 { return error(result.output) }
	os.write_file(out + '/fault-disassembly.txt', result.output)!
	println(lines.join('\n'))
}

fn main() {
	if os.args.len != 4 { eprintln('usage: inspect-probe-fault APPLICATION SERIAL OUTPUT'); exit(2) }
	out := os.real_path(os.args[3])
	root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('output must exist outside repository'); exit(2) }
	inspect(os.args[1], os.args[2], out) or { eprintln(err); exit(1) }
}
