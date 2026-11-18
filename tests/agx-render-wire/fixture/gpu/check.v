// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import gpu.agx.hw

#include <stdio.h>
#define kprintf printf
fn C.kprintf(format &char, ...) i32

struct Node { va u64 }
struct Job { vm_slot u32; vertex Node; scene Scene; vertex_event_sequence u64 }
struct Scene { scene Node }
struct Buffer { info Node; slot u32 }
struct Channels { stats_vertex Node }
struct Manager { g13_channels Channels }
struct Queue { info Node }
struct Resources { firmware_id u64 }
struct Input { vertex_command_id u32 }
struct Sample {
	job Job
	buffer Buffer
	manager Manager
	queue Queue
	resources Resources
	input Input
	attachments fw.G13MicroseqAttachments
	counter u64
	notifier u64
}

fn put32(mut bytes [0x18c]u8, at int, value u32) {
	for i in 0 .. 4 { bytes[at + i] = u8(value >> u32(i * 8)) }
}
fn put64(mut bytes [0x18c]u8, at int, value u64) {
	for i in 0 .. 8 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

// Offsets follow the packed reference StartVertex record. The existing layout
// oracle independently checks the work-command offsets used for its pointers.
fn expected_bytes(sample Sample, newer bool) [0x18c]u8 {
	abi := if newer { hw.FirmwareAbi.v13_5_partial } else { hw.FirmwareAbi.v12_3 }
	mut out := [0x18c]u8{}
	put32(mut out, 0, 0x22)
	put64(mut out, 0x04, sample.job.vertex.va + (fw.g13_vertex_tiling_params_offset_for(abi) or { panic('tiling offset') }))
	put64(mut out, 0x0c, sample.job.vertex.va + (fw.g13_vertex_job_params_1_offset_for(abi) or { panic('params offset') }))
	put64(mut out, 0x14, sample.buffer.info.va)
	put64(mut out, 0x1c, sample.job.scene.scene.va)
	put64(mut out, 0x24, sample.manager.g13_channels.stats_vertex.va + 4)
	put64(mut out, 0x2c, sample.queue.info.va)
	put32(mut out, 0x34, sample.job.vm_slot)
	put32(mut out, 0x38, 1)
	put32(mut out, 0x3c, u32(sample.resources.firmware_id))
	put32(mut out, 0x40, sample.buffer.slot)
	put64(mut out, 0x48, sample.job.vertex_event_sequence)
	put64(mut out, 0x54, sample.job.vertex.va + (fw.g13_vertex_unk_pointee_offset_for(abi) or { panic('pointee offset') }))
	put64(mut out, 0x5c, sample.job.vertex.va + (fw.g13_vertex_unk_buf_0_offset_for(abi) or { panic('job offset') }))
	put32(mut out, 0x6c, sample.input.vertex_command_id)
	for i := u32(0); i < sample.attachments.count; i++ {
		attachment := sample.attachments.list[i]
		at := 0x70 + int(i) * 16
		put64(mut out, at, attachment.address)
		put32(mut out, at + 8, attachment.size)
		put32(mut out, at + 12, u32(attachment.unk_c) | (u32(attachment.unk_e) << 16))
	}
	put32(mut out, 0x170, sample.attachments.count)
	if newer {
		put64(mut out, 0x178, sample.counter)
		put64(mut out, 0x180, sample.notifier)
		put32(mut out, 0x188, 1)
	}
	return out
}

pub fn run_checks() {
	assert fw.validate_g13_microsequence_layouts()
	mut cases := 0
	for cycle in 0 .. 100 {
		for newer in [false, true]! {
			for count in [u32(0), 1, 16]! {
				for shift in [0, 1, 7, 15]! {
					for counter in [u64(0), 1, 0x7fff_ffff_ffff_ffff, u64(1) << 63, ~u64(0)]! {
						seed := u64(cycle) << 16
						mut attachments := fw.G13MicroseqAttachments{ count: count }
						for i := u32(0); i < count; i++ {
							attachments.list[i] = fw.G13MicroseqAttachment{
								address: 0xffff_ffa0_0000_0000 + seed + u64(i) * 0x4000
								size: i * 0x12345 + 1
								unk_c: 0x17
								unk_e: u16(i % 6 + 1)
							}
						}
						sample := Sample{
							job: Job{
								vm_slot: u32(cycle % 63 + 1)
								vertex: Node{0xffff_ffa0_1000_0000 + seed}
								scene: Scene{Node{0xffff_ffa0_2000_0000 + seed}}
								vertex_event_sequence: counter
							}
							buffer: Buffer{Node{0xffff_ffa0_3000_0000 + seed}, u32(cycle)}
							manager: Manager{Channels{Node{0xffff_ffa0_4000_0000 + seed}}}
							queue: Queue{Node{0xffff_ffa0_5000_0000 + seed}}
							resources: Resources{counter}
							input: Input{u32(cycle) | 0xa500_0000}
							attachments: attachments
							counter: counter
							notifier: 0xffff_ffa0_6000_00a8 + seed
						}
						mut storage := [0x1cc]u8{init: 0xa5}
						start := 16 + shift
						written := encode(unsafe { &storage[start] }, newer, sample)
						size := if newer { 0x18c } else { 0x17c }
						assert written == u64(size)
						expected := expected_bytes(sample, newer)
						for i in 0 .. storage.len {
							value := if i >= start && i < start + size { expected[i - start] } else { u8(0xa5) }
							assert storage[i] == value, 'vertex marker/wire mismatch at ${i - start}, firmware13.5=${newer}'
						}
						cases++
					}
				}
			}
		}
	}
	println('G13 vertex start: ${cases} byte-exact cases; versioned single-cluster marker, counter/notifier, attachments and unaligned guarded writes passed')
}
