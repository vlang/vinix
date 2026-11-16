// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw

// The firmware module imports diagnostic-only hardware helpers.
#include <stdio.h>
#define kprintf printf
fn C.kprintf(format &char, ...) i32

fn source_byte(index int, cycle int) u8 {
	return u8((index * 29 + cycle * 17) % 251 + 1)
}

fn expected_work(kind string, source [0x9c0]u8, start int, counter u64) [0x9a0]u8 {
	mut out := [0x9a0]u8{}
	// These leaf-field spans are generated from the packaged Rust declarations,
	// recursively matching semantic field names, independently of native copies.
	fields := if kind == 'vertex' { vertex_fields } else if kind == 'compute' { compute_fields } else { fragment_fields }
	for field in fields {
		for i in 0 .. field[2] { out[field[1] + i] = source[start + field[0] + i] }
	}
	for i in 0 .. 8 { out[4 + i] = u8(counter >> (i * 8)) }
	set_reference_defaults(kind, mut out)
	return out
}

pub fn run_checks(selected string) {
	if selected in ['all', 'both', 'vertex'] {
		assert sizeof(fw.G13RunVertex) == vertex_old_size
		assert sizeof(fw.G13RunVertexV135) == vertex_new_size, 'vertex command size differs from source model'
	}
	if selected in ['all', 'both', 'compute'] {
		assert sizeof(fw.G13RunCompute) == compute_old_size
		assert sizeof(fw.G13RunComputeV135) == compute_new_size, 'compute command size differs from source model'
	}
	if selected in ['all', 'fragment'] {
		assert sizeof(fw.G13RunFragment) == fragment_old_size
		assert sizeof(fw.G13RunFragmentV135) == fragment_new_size, 'fragment command size differs from source model'
	}
	mut cases := 0
	for cycle in 0 .. 200 {
		for shift in [0, 1, 7, 15]! {
			for counter in [u64(0), 1, u64(1) << 63, u64(0xffff_ffa0_1234_5678), ~u64(0)]! {
				for kind in ['vertex', 'compute', 'fragment']! {
					if selected == 'both' && kind == 'fragment' { continue }
					if selected !in ['all', 'both'] && selected != kind { continue }
					old_size := if kind == 'vertex' { vertex_old_size } else if kind == 'compute' { compute_old_size } else { fragment_old_size }
					mut source := [0x9c0]u8{init: 0xa5}
					start := 16 + shift
					for i in 0 .. old_size { source[start + i] = source_byte(i, cycle) }
					expected := expected_work(kind, source, start, counter)
					if kind == 'vertex' {
						actual := fw.make_g13_vertex_v13_5(unsafe { &fw.G13RunVertex(&source[start]) }, counter)
						for i in 0 .. actual.bytes.len {
							assert actual.bytes[i] == expected[i], 'vertex work byte mismatch at ${i}'
						}
					} else if kind == 'compute' {
						actual := fw.make_g13_compute_v13_5(unsafe { &fw.G13RunCompute(&source[start]) }, counter)
						for i in 0 .. actual.bytes.len {
							assert actual.bytes[i] == expected[i], 'compute work byte mismatch at ${i}'
						}
					} else {
						actual := fw.make_g13_fragment_v13_5(unsafe { &fw.G13RunFragment(&source[start]) }, counter)
						for i in 0 .. actual.bytes.len {
							assert actual.bytes[i] == expected[i], 'fragment work byte mismatch at ${i}'
						}
					}
					for i in 0 .. source.len {
						value := if i >= start && i < start + old_size { source_byte(i - start, cycle) } else { u8(0xa5) }
						assert source[i] == value, 'work source/guard changed'
					}
					cases++
				}
			}
		}
	}
	println('G13 work commands: ${cases} complete source-modeled byte images; sizes, recursive common fields, padding, inserted/removed words, tails, counters, unaligned sources and unchanged guards passed')
}
