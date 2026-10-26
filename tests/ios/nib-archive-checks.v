// SPDX-License-Identifier: GPL-2.0-or-later
// All fixtures here are generated from source; optional inputs are read-only.
module main

import os
import nib
import nibfixture

fn put32(mut bytes []u8, at int, value u32) {
	for i in 0 .. 4 { bytes[at + i] = u8(value >> (8 * i)) }
}

fn sample() []u8 {
	mut bytes := []u8{len: 50}
	for i, b in 'NIBArchive'.bytes() { bytes[i] = b }
	put32(mut bytes, 10, 1); put32(mut bytes, 14, 9)
	put32(mut bytes, 18, 1); put32(mut bytes, 22, 50)
	bytes << [u8(0x80), 0x80, 0x81] // One NSObject, one value.
	put32(mut bytes, 26, 1); put32(mut bytes, 30, u32(bytes.len))
	bytes << u8(0x84); bytes << 'name'.bytes()
	put32(mut bytes, 34, 1); put32(mut bytes, 38, u32(bytes.len))
	bytes << [u8(0x80), 8, 0x85]; bytes << 'hello'.bytes()
	put32(mut bytes, 42, 1); put32(mut bytes, 46, u32(bytes.len))
	bytes << [u8(0x89), 0x80]; bytes << 'NSObject'.bytes(); bytes << u8(0)
	return bytes
}

fn reject(bytes []u8) {
	archive := nib.parse(bytes) or { return }
	archive.free()
	panic('malformed NIBArchive accepted')
}

fn main() {
	// Exercise every value tag, multi-byte lengths/indices and invalid references.
	mut values := [nibfixture.Value{'u8', 0, [u8(255)]},
		nibfixture.Value{'u16', 1, nibfixture.little(65535, 2)},
		nibfixture.Value{'u32', 2, nibfixture.little(0xffffffff, 4)},
		nibfixture.int_value('u64', 0xffffffffffffffff), nibfixture.flag('false', false), nibfixture.flag('true', true),
		nibfixture.Value{'float', 6, nibfixture.little(0x3fc00000, 4)}, nibfixture.real('double', -2.5),
		nibfixture.data('data', []u8{len: 200, init: 42}), nibfixture.Value{'nil', 9, []u8{}}, nibfixture.ref('ref', 0)]
	for i in 0 .. 140 { values << nibfixture.int_value('key-${i}', u64(i)) }
	full := nibfixture.encode([nibfixture.Object{'NSObject', values}])
	all := nib.parse(full)!
	assert all.values.len == 151 && all.keys.len == 151
	assert all.values[0].integer == 255 && all.values[1].integer == 65535
	assert all.values[2].integer == 0xffffffff && all.values[3].integer == u64(0xffffffffffffffff)
	assert all.values[4].kind == 4 && all.values[5].kind == 5
	assert all.values[6].real == 1.5 && all.values[7].real == -2.5
	assert all.values[8].data == []u8{len: 200, init: 42}
	assert all.values[9].kind == 9 && all.values[10].integer == 0 && all.values[150].integer == 139
	all.free()
	reject(nibfixture.encode([nibfixture.Object{'NSObject', [nibfixture.ref('ref', 1)]}]))
	reject(nibfixture.encode([nibfixture.Object{'NSObject', [nibfixture.Value{'nan', 7, nibfixture.little(0x7ff8000000000000, 8)}]}]))
	mut bytes := sample()
	archive := nib.parse(bytes)!
	assert archive.classes == ['NSObject'] && archive.keys == ['name']
	assert archive.objects.len == 1 && archive.values.len == 1
	assert archive.values[0].data.bytestr() == 'hello'
	bytes[61] = `X`
	assert archive.values[0].data.bytestr() == 'hello' // Independent snapshot.
	archive.free()
	unsafe { bytes.free() }
	valid := sample()
	for length in 0 .. valid.len { reject(valid[..length]) }
	for at in [10, 14, 18, 22, 26, 30, 34, 38, 42, 46, 50, 51, 52, 53, 58, 59, 60, 66, 67, 76]! {
		mut bad := valid.clone(); bad[at] = 0xff; reject(bad); unsafe { bad.free() }
	}
	mut trailing := valid.clone(); trailing << u8(0); reject(trailing)
	unsafe { trailing.free(); valid.free() }
	println('NIBArchive synthetic checks: PASS')
	for path in os.args[1..] {
		input := os.read_bytes(path)!
		doc := nib.parse(input)!
		println('${path}: ${doc.objects.len} objects, ${doc.keys.len} keys, ${doc.values.len} values, ${doc.classes.len} classes')
		for i, object in doc.objects {
			println('object ${i}: ${doc.classes[object.class_id]}')
			for value in doc.values[object.first..object.first + object.count] {
				detail := match value.kind {
					6, 7 { value.real.str() }
					8 { value.data.hex() }
					else { value.integer.str() }
				}
				println('  ${doc.keys[value.key]} type=${value.kind} ${detail}')
			}
		}
		doc.free(); unsafe { input.free() }
	}
}
