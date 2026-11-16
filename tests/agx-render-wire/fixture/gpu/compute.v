// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw

fn compute_finalize_bytes(command fw.G13MicroseqFinalizeCompute, newer bool, flag u64) [0x18c]u8 {
	mut out := [0x18c]u8{}
	put32(mut out, 0, 0x2a)
	put64(mut out, 0x04, command.stats)
	put64(mut out, 0x0c, command.work_queue)
	put32(mut out, 0x14, command.vm_slot)
	delta := if newer { 4 } else { 0 }
	if !newer { put32(mut out, 0x18, command.unk_18) }
	put64(mut out, 0x1c - delta, command.job_params_2)
	put32(mut out, 0x24 - delta, command.unk_24)
	put32(mut out, 0x28 - delta, command.uuid)
	put64(mut out, 0x2c - delta, command.fw_stamp)
	put32(mut out, 0x34 - delta, command.stamp_value)
	for i, value in [command.unk_38, command.unk_3c, command.unk_40, command.unk_44,
		command.unk_48, command.unk_4c, command.unk_50, command.unk_54, command.unk_58]! {
		put32(mut out, 0x38 - delta + i * 4, value)
	}
	put32(mut out, 0x5c - delta, u32(command.restart_branch_offset))
	put32(mut out, 0x60 - delta, command.has_attachments)
	if newer { put64(mut out, 0x6d, flag) }
	return out
}

fn check_compute_bytes(storage [0x1cc]u8, start int, size int, expected [0x18c]u8) {
	for i in 0 .. storage.len {
		value := if i >= start && i < start + size { expected[i - start] } else { u8(0xa5) }
		assert storage[i] == value, 'compute finalizer flag/wire mismatch at ${i - start}'
	}
}

pub fn run_compute_finalize_checks() {
	mut cases := 0
	for cycle in 0 .. 100 {
		for newer in [false, true]! {
			for shift in [0, 1, 7, 15]! {
				for attachments in [u32(0), 1]! {
					for flag in [u64(0), 1, u64(1) << 63, u64(0xffff_ffa0_1234_0305), ~u64(0)]! {
						seed := u64(cycle) << 16
						command := fw.G13MicroseqFinalizeCompute{
							header: 0x2a
							stats: 0xffff_ffa0_1000_0000 + seed
							work_queue: 0xffff_ffa0_2000_0000 + seed
							vm_slot: u32(cycle % 63 + 1)
							unk_18: 0xdecafbad
							job_params_2: 0xffff_ffa0_3000_01fc + seed
							unk_24: 0x12345678
							uuid: u32(cycle) | 0xa500_0000
							fw_stamp: 0xffff_ffa0_4000_0000 + seed
							stamp_value: u32(cycle) << 24
							unk_38: 0x11111111
							unk_3c: 0x22222222
							unk_40: 0x33333333
							unk_44: 0x44444444
							unk_48: 0x55555555
							unk_4c: 0x66666666
							unk_50: 0x77777777
							unk_54: 0x88888888
							unk_58: 0x99999999
							restart_branch_offset: -i32(0x154 + cycle * 4)
							has_attachments: attachments
						}
						mut storage := [0x1cc]u8{init: 0xa5}
						start := 16 + shift
						size := if newer { 0x7c } else { 0x64 }
						written := write_g13_finalize_compute(unsafe { &storage[start] }, newer, unsafe { &command }, flag)
						assert written == u64(size)
						check_compute_bytes(storage, start, size, compute_finalize_bytes(command, newer, flag))
						// The same address must reach both ends of the compute microsequence.
						begin := fw.G13MicroseqStartCompute{ header: 0x29 }
						counter := ~u64(0) - u64(cycle)
						notifier := 0xffff_ffa0_5000_00a8 + seed
						mut begin_storage := [0x1cc]u8{init: 0xa5}
						begin_size := if newer { 0x16c } else { 0x154 }
						assert write_g13_start_compute(unsafe { &begin_storage[start] }, newer,
							unsafe { &begin }, flag, counter, notifier) == u64(begin_size)
						mut expected := [0x18c]u8{}
						put32(mut expected, 0, 0x29)
						if newer {
							put64(mut expected, 0x154, flag)
							put64(mut expected, 0x15c, counter)
							put64(mut expected, 0x164, notifier)
						}
						check_compute_bytes(begin_storage, start, begin_size, expected)
						cases++
					}
				}
			}
		}
	}
	println('G13 compute finalizer: ${cases} byte-exact start/finalize pairs; shared flag, both ABIs, complete fields/padding, backward branches and guarded unaligned writes passed')
}
