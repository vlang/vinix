// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

#include <stdio.h>
#define kprintf printf
fn C.kprintf(format &char, ...) i32

struct Input { has_result bool }
struct Buffer { address u64 }
fn (buffer &Buffer) cpu_address() voidptr { return unsafe { voidptr(buffer.address) } }
struct Job { vertex Buffer fragment Buffer command Buffer }

pub fn run_checks() {
	mut cases := 0
	for cycle in 0 .. 128 {
		for modern in [false, true] {
			abi := if modern { 1 } else { 0 }
			for legacy in [false, true] {
				for vertex_mask in 0 .. 4 {
					for fragment_mask in 0 .. 4 {
						vertex := [if vertex_mask & 1 != 0 { u64(0xffffffae12345678) + u64(cycle) } else { u64(0) }, if vertex_mask & 2 != 0 { ~u64(cycle) } else { u64(0) }]!
						fragment := [if fragment_mask & 1 != 0 { u64(0xffffffae87654321) + u64(cycle) } else { u64(0) }, if fragment_mask & 2 != 0 { ~u64(cycle + 128) } else { u64(0) }]!
						sizes := render_sizes(legacy, modern, vertex, fragment)
						assert sizes[0] == reference_sizes[0][abi] + if legacy || vertex_mask != 0 { 2 * reference_timestamp_sizes[abi] } else { u64(0) }, 'vertex timestamp selection/size'
						assert sizes[1] == reference_sizes[1][abi] + if legacy || fragment_mask != 0 { 2 * reference_timestamp_sizes[abi] } else { u64(0) }, 'fragment timestamp selection/size'
						assert compute_size(legacy, modern, vertex) == reference_sizes[2][abi] + if legacy || vertex_mask != 0 { 2 * reference_timestamp_sizes[abi] } else { u64(0) }, 'compute timestamp selection/size'
						for kind in 0 .. 3 {
							mut image := [0xb00]u8{init: 0xa5}
							pair := if kind == 1 { fragment } else { vertex }
							match kind { 0 { populate_vertex(unsafe { &image[0] }, modern, pair) } 1 { populate_fragment(unsafe { &image[0] }, modern, pair) } else { populate_compute(unsafe { &image[0] }, modern, pair) } }
							offset := reference_offsets[kind][abi]
							for index in 0 .. image.len {
								expected := if index >= offset && index < offset + 16 { u8(pair[(index - offset) / 8] >> (((index - offset) % 8) * 8)) } else { u8(0xa5) }
								assert image[index] == expected, 'resolved timestamp pair/neighbor bytes'
							}
							cases++
						}
					}
				}
			}
		}
	}
	println('G13 resolved timestamp inputs: ${cases} complete command-pair images, independent engine/phase selection, source-derived microsequence extents and legacy controls passed')
}
