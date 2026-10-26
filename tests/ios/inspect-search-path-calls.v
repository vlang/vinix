// SPDX-License-Identifier: GPL-2.0-or-later
// List direct callers of a verified Mach-O import stub and their instructions.
module main

import encoding.binary
import macho
import os
import strconv

fn main() {
	if os.args.len != 4 { panic('usage: inspect-search-path-calls APPLICATION STUB_HEX EXTERNAL_OUT') }
	application := os.real_path(os.args[1])
	stub := strconv.parse_uint(os.args[2].trim_string_left('0x'), 16, 64)!
	out := os.real_path(os.args[3])
	root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { panic('output must be external') }
	image := macho.parse(os.read_bytes(application)!)!
	mut lines := []string{}
	for segment in image.segments {
	for section in segment.sections {
		if section.flags & 0x80000400 == 0 { continue }
		if section.address < segment.address { panic('invalid section address') }
		relative := section.address - segment.address
		if relative > segment.filesize || section.size > segment.filesize - relative {
			panic('code section is not file backed')
		}
		start := segment.fileoff + relative
		if start > u64(image.data.len) || section.size > u64(image.data.len) - start { panic('invalid code range') }
		for offset := u64(0); offset + 4 <= section.size; offset += 4 {
			word := binary.little_endian_u32(image.data[int(start + offset)..int(start + offset + 4)])
			if word & 0x7c000000 != 0x14000000 { continue }
			pc := section.address + offset
			delta := (i64(word & 0x03ffffff) << 38) >> 36
			if u64(i64(pc) + delta) != stub { continue }
			lines << 'SEARCH-PATH-CALL: pc=0x${pc.hex()} stub=0x${stub.hex()}'
			result := os.exec(['/opt/homebrew/opt/llvm/bin/llvm-objdump', '--disassemble',
				'--no-show-raw-insn', '--start-address=0x${(pc - 48).hex()}',
				'--stop-address=0x${(pc + 16).hex()}', application])
			if result.exit_code != 0 { panic(result.output) }
			lines << result.output
		}
	}
	}
	if lines.len == 0 { panic('no direct callers found') }
	os.write_file(out + '/search-path-calls.txt', lines.join('\n') + '\n')!
	println('search-path call sites: ${lines.len / 2}')
}
