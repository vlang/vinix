// SPDX-License-Identifier: MIT
module emulatorbuild

import hosttest
import fixturehost
import os
import policyhost

fn word(data []u8, offset int, big bool) !u32 {
	if offset < 0 || offset > data.len - 4 { return error('Truncated ELF or cartridge word') }
	mut value := u32(0)
	for i in 0 .. 4 { value = (value << 8) | data[offset + if big { i } else { 3 - i }] }
	return value
}

fn half(data []u8, offset int, big bool) !u32 {
	if offset < 0 || offset > data.len - 2 { return error('Truncated ELF halfword') }
	return if big { (u32(data[offset]) << 8) | data[offset + 1] } else { (u32(data[offset + 1]) << 8) | data[offset] }
}

fn put_word(mut data []u8, offset int, value u32) {
	for i in 0 .. 4 { data[offset + i] = u8(value >> (8 * (3 - i))) }
}

pub fn segments(path string, base u32, limit u32, big bool) ![]u8 {
	data := os.read_bytes(path)!
	if data.len < 52 || data[..4] != [u8(0x7f), `E`, `L`, `F`] || data[4] != 1 ||
		data[5] != if big { 2 } else { 1 } || half(data, 18, big)! != 8 {
		return error('Expected a 32-bit MIPS ELF: ' + path)
	}
	offset, stride, count := word(data, 28, big)!, half(data, 42, big)!, half(data, 44, big)!
	if stride < 32 || u64(offset) + u64(stride) * count > u64(data.len) { return error('Truncated ELF segment table') }
	mut image := []u8{}
	for index in 0 .. int(count) {
		at := int(offset) + index * int(stride)
		if word(data, at, big)! != 1 { continue }
		start, address, size, memory := word(data, at + 4, big)!, word(data, at + 8, big)!,
			word(data, at + 16, big)!, word(data, at + 20, big)!
		if address < base || u64(address) + memory > limit { return error(os.file_name(path) + ': load segment is outside the program region') }
		if size > memory || u64(start) + size > u64(data.len) { return error('Truncated ELF load segment') }
		needed := int(address - base + memory)
		if needed > image.len { image << []u8{len: needed - image.len} }
		for i in 0 .. int(size) { image[int(address - base) + i] = data[int(start) + i] }
	}
	return image
}

pub fn checksum(mut rom []u8) ! {
	if rom.len < 24 { return error('Cartridge header is truncated') }
	mut padded := rom.clone()
	if padded.len < 0x101000 { padded << []u8{len: 0x101000 - padded.len} }
	mut t1, mut t2, mut t3, mut t4, mut t5, mut t6 := u32(0xf8ca4ddc), u32(0xf8ca4ddc),
		u32(0xf8ca4ddc), u32(0xf8ca4ddc), u32(0xf8ca4ddc), u32(0xf8ca4ddc)
	for offset := 0x1000; offset < 0x101000; offset += 4 {
		value := word(padded, offset, true)!
		total := t6 + value
		if total < t6 { t4++ }
		t6 = total
		t3 ^= value
		shift := value & 31
		rotated := (value << shift) | (value >> ((32 - shift) & 31))
		t5 += rotated
		t2 ^= if t2 > value { rotated } else { t6 ^ value }
		t1 += t5 ^ value
	}
	put_word(mut rom, 0x10, t6 ^ t4 ^ t3)
	put_word(mut rom, 0x14, t5 ^ t2 ^ t1)
}

fn generate(core string, destination string) ! {
	result := hosttest.generate_module_with_capture(core, destination, 'x86', []string{}, module_capture)!
	print(result.stdout)
	eprint(result.stderr)
}

fn module_capture(argv []string, _log string, _timeout int, env map[string]string) !hosttest.Result {
	policyhost.command_checkpoint()!
	result := fixturehost.capture_owned_bounded(argv, env, policyhost.caller_arch(), '', -1,
		policyhost.command_interrupted, false)!
	return hosttest.Result{result.stdout, result.stderr, result.status}
}

fn n64_homebrew(output string, directory string) ! {
	mkdir(output)!
	source := hosttest.root() + '/build-support/n64-homebrew'
	clang, linker := tool('clang', directory)!, tool('ld.lld', directory)!
	flags := ['--target=mips-none-elf', '-march=mips3', '-mabi=32', '-mno-abicalls',
		'-fno-pic', '-G0', '-msoft-float', '-ffreestanding', '-fno-builtin',
		'-fno-stack-protector', '-O2', '-Wall', '-Wextra', '-Werror']
	for file in ['ipl3.S', 'start.S', 'paddlecore/mmio.S'] {
		run([clang, ...flags, '-c', source + '/' + file, '-o', output + '/' + os.file_name(file) + '.o'])!
	}
	core, generated := source + '/paddlecore', output + '/paddle.generated.c'
	generate(core, generated)!
	run([clang, ...flags, '-Wno-unused-function', '-Wno-unused-parameter', '-I' + core,
		'-I' + core + '/freestanding', '-c', generated, '-o', output + '/paddle.v.o'])!
	for name in ['ipl3', 'game'] {
		objects := if name == 'ipl3' { ['ipl3.S.o'] } else { ['start.S.o', 'paddle.v.o', 'mmio.S.o'] }
		run([linker, '-m', 'elf32btsmip', '-T', source + '/' + name + '.ld',
			...objects.map(output + '/' + it), '-o', output + '/' + name + '.elf'])!
	}
	mut rom := []u8{len: 0x100000}
	for i, value in [u32(0x80371240), 0x0000000f, 0x80000400, 0] { put_word(mut rom, i * 4, value) }
	for i, b in ('VINIX PADDLE' + ' '.repeat(8)).bytes() { rom[0x20 + i] = b }
	for i, b in 'NDEE\x30'.bytes() { rom[0x3b + i] = b }
	boot := segments(output + '/ipl3.elf', 0xa4000040, 0xa4001000, true)!
	program := segments(output + '/game.elf', 0x80000400, 0x800ff400, true)!
	for i, b in boot { rom[0x40 + i] = b }
	for i, b in program { rom[0x1000 + i] = b }
	checksum(mut rom)!
	os.write_file_array(output + '/paddle.z64', rom)!
	hosttest.module_copy_file_preserving_stat(source + '/LICENSE', output + '/LICENSE')!
	println(output + '/paddle.z64')
}

pub fn image_header(data []u8) string {
	mut lines := []string{}
	for offset := 0; offset < data.len; offset += 16 {
		end := if offset + 16 < data.len { offset + 16 } else { data.len }
		lines << data[offset..end].map('0x' + hex_width(it, 2)).join(',')
	}
	return '// Generated from iopcore; SPDX-License-Identifier: MIT\nstatic const unsigned char iop_image[] = {\n' + lines.join(',\n') + '\n};\n'
}

fn ps2_homebrew(output string, directory string) ! {
	mkdir(output)!
	source := hosttest.root() + '/build-support/ps2-homebrew'
	clang, linker := tool('clang', directory)!, tool('ld.lld', directory)!
	common := ['--target=mipsel-none-elf', '-mno-abicalls', '-fno-pic', '-G0', '-msoft-float',
		'-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-O2', '-Wall', '-Wextra', '-Werror']
	for cpu in ['iop', 'ee'] {
		flags := [...common, '-march=' + if cpu == 'iop' { 'mips1' } else { 'mips3' },
			'-mabi=' + if cpu == 'iop' { '32' } else { 'n32' }]
		mut native := ['start-' + cpu + '.S']
		if cpu == 'ee' { native << 'eecore/sync.S' }
		for file in native {
			mkdir(os.dir(output + '/' + file + '.o'))!
			run([clang, ...flags, '-I' + output, '-c', source + '/' + file, '-o', output + '/' + file + '.o'])!
		}
		core := source + '/' + cpu + 'core'
		generated := output + '/' + cpu + '.generated.c'
		generate(core, generated)!
		object := output + '/' + cpu + '.v.o'
		run([clang, ...flags, '-Wno-unused-function', '-Wno-unused-parameter', '-I' + core,
			'-I' + source + '/freestanding', '-I' + output, '-c', generated, '-o', object])!
		elf := output + if cpu == 'iop' { '/iop.elf' } else { '/paddle.elf' }
		run([linker, '-m', if cpu == 'iop' { 'elf32ltsmip' } else { 'elf32ltsmipn32' }, '-T',
			source + '/' + cpu + '.ld', output + '/start-' + cpu + '.S.o', object,
			...native[1..].map(output + '/' + it + '.o'), '-o', elf])!
		if cpu == 'iop' {
			hosttest.module_write_text(output + '/iop-image.h', image_header(segments(elf, 0x1000, 0x00100000, false)!))!
		} else {
			mut bytes := os.read_bytes(elf)!
			if bytes.len < 8 { return error('Emotion Engine ELF is truncated') }
			bytes[7] = 0x56
			os.write_file_array(elf, bytes)!
		}
	}
	hosttest.module_copy_file_preserving_stat(source + '/LICENSE', output + '/LICENSE')!
	println(output + '/paddle.elf')
}
