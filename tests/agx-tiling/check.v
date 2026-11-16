// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

#include <stdio.h>
#define kprintf printf
fn C.kprintf(format &char, ...) i32

struct Input {
mut:
	width u32 = 1
	height u32 = 1
	layers u32 = 1
	utile_width u32 = 32
	utile_height u32 = 32
	samples u32 = 1
	sample_bits u32
	ppp u32
	helper u32
}

// Independent mathematical implementations for the translated Rust helpers.
// All modeled divisors are nonzero powers of two and values are bounded by
// the source's validated 16K dimensions and 2048 layers.
fn reference_div_ceil(value u64, divisor u64) u64 { return (value + divisor - 1) / divisor }
fn reference_align(value u64, alignment u64) u64 { return reference_div_ceil(value, alignment) * alignment }

fn check_valid(input Input) {
	actual := g13_tile_info(input.width, input.height, input.layers, input.utile_width,
		input.utile_height, input.samples, input.ppp, input.helper) or { panic('native refused source-valid geometry') }
	expected := reference_tile(input)
	assert actual == expected, 'native tiling differs from selected Rust expressions: ${input}'
	// The parameter record contains only integer fields and declared byte
	// padding. Compare its entire wire image, including all 112 reserved bytes.
	a := unsafe { &u8(&actual.params) }
	e := unsafe { &u8(&expected.params) }
	for i in 0 .. int(sizeof(actual.params)) { assert unsafe { a[i] == e[i] }, 'packed tiling byte ${i}' }
}

pub fn run_checks() {
	mut valid := 0
	dimensions := [u32(1), 15, 16, 17, 31, 32, 33, 127, 128, 129, 511, 512, 513, 16383, 16384]
	for width in dimensions {
		for height in dimensions {
			for layers in [u32(1), 2, 3, 2047, 2048] {
				for utile in [[u32(32), 32]!, [u32(32), 16]!, [u32(16), 16]!] {
					for bits in 0 .. 3 {
						for words in [[u32(0), 0]!, [u32(0xffff_ffff), 0x8000_0000]!, [u32(0xa5c3_19ef), 0x5a3c_e610]!] {
							check_valid(Input{width: width, height: height, layers: layers, utile_width: utile[0], utile_height: utile[1], samples: u32(1) << bits, sample_bits: u32(bits), ppp: words[0], helper: words[1]})
							valid++
						}
					}
				}
			}
		}
	}
	mut invalid := 0
	for field in 0 .. 6 {
		for value in [u32(0), 3, 8, 16, 17, 31, 16385, ~u32(0)] {
			mut input := Input{}
			match field {
				0 { if value > 0 && value <= 16384 { continue }; input.width = value }
				1 { if value > 0 && value <= 16384 { continue }; input.height = value }
				2 { if value > 0 && value <= 2048 { continue }; input.layers = value }
				3 { if value in [u32(16), 32] { continue }; input.utile_width = value }
				4 { if value in [u32(16), 32] { continue }; input.utile_height = value }
				else { if value in [u32(1), 2, 4] { continue }; input.samples = value }
			}
			if _ := g13_tile_info(input.width, input.height, input.layers, input.utile_width, input.utile_height, input.samples, input.ppp, input.helper) { assert false, '${input}' }
			invalid++
		}
	}
	// Reversed 16x32 is deliberately unsupported even though its area matches
	// the accepted 32x16 layout.
	if _ := g13_tile_info(1, 1, 1, 16, 32, 1, 0, 0) { assert false }
	invalid++
	println('G13 tiling: ${valid} source-modeled complete results and packed images; ${invalid} invalid geometries rejected; 16K edges, uTiles, samples, 2048 layers, >4GiB sizes, macrotiles, TVB blocks, layer metadata, full-width control words and reserved bytes passed')
}
