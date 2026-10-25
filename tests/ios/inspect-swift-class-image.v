// SPDX-License-Identifier: GPL-2.0-or-later
// Offline inventory only: imported pointer placeholders are never executed.
module main

import os
import macho

struct View {
	image macho.Image
	fixups map[u64]u64
}

fn (v View) offset(address u64, size u64) !int {
	for s in v.image.segments {
		if s.name != '__PAGEZERO' && address >= s.address && address - s.address <= s.filesize
			&& size <= s.filesize - (address - s.address) {
			return int(s.fileoff + address - s.address)
		}
	}
	return error('unmapped 0x${address.hex()} + ${size}')
}

fn (v View) number(address u64, size int) !u64 {
	offset := v.offset(address, u64(size))!
	mut n := u64(0)
	for i in 0 .. size { n |= u64(v.image.data[offset + i]) << (8 * i) }
	return n
}

fn (v View) ptr(address u64) !u64 {
	if p := v.fixups[address] { return p }
	return v.number(address, 8)!
}

fn (v View) string_at(address u64) !string {
	mut b := []u8{}
	for i in 0 .. 1024 {
		x := u8(v.number(address + u64(i), 1)!)
		if x == 0 { return b.bytestr() }
		b << x
	}
	return error('long string')
}

__global import_labels = map[u64]string{}
fn imported(library string, symbol string) !u64 {
	address := u64(0x700000000000) + u64(import_labels.len) * 8
	import_labels[address] = '${library}:${symbol}'
	return address
}

fn main() {
	if os.args.len != 2 { panic('usage: inspect IMAGE') }
	img := macho.parse(os.read_bytes(os.args[1])!)!
	layout := img.layout(4096)!
	mut f := map[u64]u64{}
	for p in img.plan_fixups(layout, layout.base, imported)! { f[layout.base + p.offset] = p.value }
	v := View{img, f}
	mut total := 0
	mut swift := 0
	for s in img.segments {
		println('SEGMENT ${s.name} address=0x${s.address.hex()} size=0x${s.size.hex()} file=0x${s.filesize.hex()} prot=${s.prot} flags=0x${s.flags.hex()}')
		for sec in s.sections {
			if sec.name !in ['__objc_classlist', '__objc_nlclslist'] { continue }
			println('${sec.name} count=${sec.size / 8}')
			for i := u64(0); i < sec.size; i += 8 {
				cls := v.ptr(sec.address + i)!
				ro := v.ptr(cls + 32)! & ~u64(7)
				flags := v.number(ro, 4)!
				total++
				if flags & 0x40 == 0 { continue }
				swift++
				name := v.string_at(v.ptr(ro + 24)!)!
				println('SWIFT ${name} class=0x${cls.hex()} ro=0x${ro.hex()} flags=0x${flags.hex()} parent=0x${v.ptr(cls + 8)!.hex()} initializer=0x${v.ptr(ro + 72)!.hex()}')
				meta := v.ptr(cls)!
				mr := v.ptr(meta + 32)! & ~u64(7)
				println('META class=0x${meta.hex()} ro=0x${mr.hex()} flags=0x${v.number(mr, 4)!.hex()} bits=${v.ptr(meta + 32)! & 7}')
				println('RO start=${v.number(ro + 4,4)!} size=${v.number(ro + 8,4)!}')
				list := v.ptr(ro + 48)!
				if list != 0 {
					count := v.number(list + 4,4)!
					if count > 64 || v.number(list,4)! != 32 { panic('unsupported ivar inventory') }
					for j in u64(0)..count {
						e := list + 8 + j * 32; cell := v.ptr(e)!
						println('IVAR ${v.string_at(v.ptr(e + 8)!)!} cell=0x${cell.hex()} offset=${v.number(cell,8)!} size=${v.number(e + 28,4)!} align=${v.number(e + 24,4)!}')
					}
				}
				for j in 0 .. 13 {
					value := v.ptr(cls + u64(j) * 8)!
					println('  +${j * 8}: 0x${value.hex()} ${import_labels[value]}')
				}
				desc := v.ptr(cls + 64)!
				if desc > layout.base && desc < layout.base + layout.size {
					for j in 0 .. 18 { println('  descriptor+${j * 4}: 0x${v.number(desc + u64(j) * 4, 4)!.hex()}') }
				}
			}
		}
	}
	println('TOTAL entries=${total} swift_initializers=${swift}')
}
