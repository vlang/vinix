// SPDX-License-Identifier: GPL-2.0-or-later
// Locate direct ARM64 calls to a Mach-O import using the installed LLVM tools.
module main

import encoding.binary
import os
import strconv

fn invoke(args []string) string {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	p.set_redirect_stdio()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	if p.code != 0 { panic(p.stderr_slurp()) }
	p.close()
	return output
}

fn main() {
	if os.args.len != 3 { panic('usage: trace-import MACH-O _symbol') }
	path := os.args[1]
	symbol := os.args[2]
	llvm := '/opt/homebrew/opt/llvm/bin/llvm-objdump'
	indirect := invoke([llvm, '--macho', '--indirect-symbols', path])
	mut stub := u64(0)
	mut in_stubs := false
	for line in indirect.split_into_lines() {
		if line.starts_with('Indirect symbols for ') {
			in_stubs = line.contains('(__TEXT,__stubs)')
		}
		fields := line.fields()
		if in_stubs && fields.len == 3 && fields[2] == symbol {
			stub = strconv.parse_uint(fields[0].trim_string_left('0x'), 16, 64) or { panic(err) }
			break
		}
	}
	if stub == 0 { panic('import stub not found') }
	println('${symbol} stub 0x${stub:x}')
	data := os.read_bytes(path) or { panic(err) }
	if data.len < 32 || binary.little_endian_u32(data[..4]) != 0xfeedfacf || binary.little_endian_u32(data[4..8]) != 0x100000c {
		panic('expected thin ARM64 Mach-O')
	}
	mut offset := 32
	for _ in 0 .. int(binary.little_endian_u32(data[16..20])) {
		if offset > data.len - 8 { panic('truncated load command') }
		cmd := binary.little_endian_u32(data[offset..offset + 4])
		size := int(binary.little_endian_u32(data[offset + 4..offset + 8]))
		if size < 8 || offset + size > data.len { panic('invalid load command') }
		if cmd == 0x19 {
			if size < 72 { panic('truncated segment') }
			sections := int(binary.little_endian_u32(data[offset + 64..offset + 68]))
			if sections > (size - 72) / 80 { panic('truncated section table') }
			for section in 0 .. sections {
				s := offset + 72 + 80 * section
				if data[s..s + 6].bytestr() != '__text' { continue }
				address := binary.little_endian_u64(data[s + 32..s + 40])
				length := int(binary.little_endian_u64(data[s + 40..s + 48]))
				start := int(binary.little_endian_u32(data[s + 48..s + 52]))
				if length < 0 || start > data.len || length > data.len - start {
					panic('invalid text range')
				}
				for i := start; i + 4 <= start + length; i += 4 {
					instruction := binary.little_endian_u32(data[i..i + 4])
					if instruction & 0x7c000000 != 0x14000000 { continue }
					mut delta := i64(instruction & 0x3ffffff)
					if delta & 0x2000000 != 0 { delta -= 0x4000000 }
					pc := address + u64(i - start)
					if u64(i64(pc) + delta * 4) != stub { continue }
					kind := if instruction & 0x80000000 != 0 { 'CALL' } else { 'TAIL' }
					println('${kind} ${symbol} @ 0x${pc:x}')
					start_address := pc - 128
					stop_address := pc + 40
					print(invoke([llvm, '-d', '--start-address=0x${start_address:x}',
						'--stop-address=0x${stop_address:x}', path]))
				}
			}
		}
		offset += size
	}
}
