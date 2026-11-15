// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_memory_vector_serialization_and_atomic_store_guards() {
	mut checks := 0
	for bits in [u32(8), 16, 24, 32, 40, 48, 56, 64]! {
		for count in 1 .. 17 {
			bytes := int(bits / 8) * count
			for sample in 0 .. 256 {
				mut input := []u8{len: bytes + 4, init: u8(index * 37 + sample)}
				mut output := []u8{len: bytes + 6, init: 0xcc}
				value := loaded_memory_vector(input[1..], bits, count)!
				stored_memory_vector(mut output[3..], value, bits, count)!
				assert output[..3] == [u8(0xcc), 0xcc, 0xcc]
				assert output[3..3 + bytes] == input[1..1 + bytes]
				for b in output[3 + bytes..] {
					assert b == 0xcc
				}
				unsafe {
					input.free()
					output.free()
				}
				checks++
			}
			for lane in 0 .. count {
				for tag in [IntegerValue{ poison: true }, IntegerValue{ aggregate: true },
					IntegerValue{ vector: true }] {
					mut source := ScalarVectorValue{}
					mut output := []u8{len: bytes, init: 0xcc}
					source.lanes[lane] = tag
					if _ := stored_memory_vector(mut output, source, bits, count) {
						assert false
					}
					for b in output {
						assert b == 0xcc
					}
					source.lanes[lane] = IntegerValue{}
					source.undef = u16(1) << lane
					if _ := stored_memory_vector(mut output, source, bits, count) {
						assert false
					}
					for b in output {
						assert b == 0xcc
					}
					unsafe { output.free() }
				}
			}
		}
	}
	mut short := [u8(0xcc)]
	for bits in [u32(0), 1, 7, 9, 65]! {
		if _ := loaded_memory_vector(short, bits, 1) {
			assert false
		}
		if _ := stored_memory_vector(mut short, ScalarVectorValue{}, bits, 1) {
			assert false
		}
	}
	for count in [0, 17] {
		if _ := loaded_memory_vector(short, 8, count) {
			assert false
		}
	}
	if _ := loaded_memory_vector(short, 16, 1) {
		assert false
	}
	if _ := stored_memory_vector(mut short, ScalarVectorValue{}, 8, 2) {
		assert false
	}
	assert short == [u8(0xcc)]
	assert checks == 32768
	println('AIR-MEMORY-VECTOR-UNIT: ${checks} raw-byte round trips; every poison/undef/tag position rejects before writes; shape/extent guards PASS')
}
