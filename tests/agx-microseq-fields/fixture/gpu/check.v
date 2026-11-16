// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

#include <stdio.h>
#define kprintf printf
fn C.kprintf(format &char, ...) i32

struct Record {
	kind string
	old_size int
	new_size int
}

fn pattern(index int, cycle int) u8 { return u8((index * 29 + cycle * 17) % 251 + 1) }

pub fn run_checks(selected string) {
	validate_layouts()
	mut cases := 0
	for cycle in 0 .. 100 {
		for source_shift in [0, 1, 7, 15]! {
			for destination_shift in [0, 1, 7, 15]! {
				for counter in [u64(0), 1, u64(1) << 63, u64(0xffff_ffa0_1234_5678), ~u64(0)]! {
					notifier := counter ^ u64(0xffff_ffa1_2345_6789)
					flag := ~counter ^ u64(0x11_2233_4455_6677)
					for record in records {
						if selected != 'all' && record.kind != selected { continue }
						mut source := [0x240]u8{init: 0xa5}
						mut destination := [0x240]u8{init: 0xa5}
						start := 16 + source_shift
						at := 16 + destination_shift
						for i in 0 .. record.old_size { source[start + i] = pattern(i, cycle) }
						image := expected(record.kind, source, start, counter, notifier, flag)
						written := convert(record.kind, unsafe { voidptr(&source[start]) }, unsafe { voidptr(&destination[at]) }, counter, notifier, flag)
						assert written == record.new_size
						for i in 0 .. destination.len {
							value := if i >= at && i < at + record.new_size { image[i - at] } else { u8(0xa5) }
							assert destination[i] == value, '${record.kind} microsequence byte mismatch at ${i - at}'
						}
						for i in 0 .. source.len {
							value := if i >= start && i < start + record.old_size { pattern(i - start, cycle) } else { u8(0xa5) }
							assert source[i] == value, 'microsequence source/guard changed'
						}
						cases++
					}
				}
			}
		}
	}
	println('G13 start/finalize fields: ${cases} complete source-modeled images; all six records, old typed member offsets, common fields, attachments, reserved tails, inserted words, removed words, full-width arguments, unaligned sources/destinations and unchanged guards passed')
}
