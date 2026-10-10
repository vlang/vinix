// SPDX-License-Identifier: GPL-2.0-or-later
module ans

import anscore
import errno
import resource
import stat

fn status_disk(index u32, partition int) AnsBlock {
	anscore.set_namespace_id(index, u64(91 + index))
	return AnsBlock{
		stat:      stat.Stat{
			rdev:    if partition < 0 { u64(91 + index) } else { u64(150 + index) }
			size:    if partition < 0 { 4096 * 512 } else { 2048 * 512 }
			blksize: 512
		}
		ns_index:  index
		partition: partition
		offset:    if partition < 0 { 0 } else { 8 * 512 }
	}
}

fn enable_writes() {
	anscore.model_enable_writes()
}

fn test_ans_status_shares_namespace_counters_and_preserves_partition_geometry() {
	model := anscore.model_setup(0, 0, 0)
	defer { anscore.model_free(model) }
	ans_ready = true
	mut whole := status_disk(0, -1)
	mut part := status_disk(0, 0)
	mut second := status_disk(1, -1)
	mut box := resource.Resource(unsafe { &part })
	initial := resource.block_status(mut box) or { panic('Missing ANS status') }
	assert sizeof(initial) == 128 && initial.version == 1 && initial.flags == 21
	assert initial.bytes == 2048 * 512 && initial.sector == 512 && initial.start == 4096
	assert initial.disk_id == 91 && initial.disk_id != part.stat.rdev
	assert initial.slot == u64(-1) && initial.generation == 0 && initial.reserved == 0
	enable_writes()
	ans_ready = false
	assert part.block_status().flags == 23
	ans_ready = true
	mut bytes := [513]u8{}
	bytes[0] = 0x73
	bytes[512] = 0x94
	assert part.read(unsafe { nil }, unsafe { &bytes[1] }, 7, 511) or { -1 } == 511
	assert bytes[0] == 0x73 && bytes[512] == 0x94
	assert bytes[1] == u8(7 * 17 + 2)
	bytes[1] = 0x31
	bytes[511] = 0xc7
	assert part.write(unsafe { nil }, unsafe { &bytes[1] }, 7, 511) or { -1 } == 511
	assert model.write_first == 2 && model.write_last == u8(511 * 17 + 2)
	assert model.write_at_7 == 0x31 && model.write_at_517 == 0xc7
	part.sync(unsafe { nil }) or { panic('ANS flush failed') }
	first := whole.block_status()
	partition_status := part.block_status()
	assert first.flags == 5 && partition_status.flags == 20
	assert first.reads == 2 && first.read_bytes == 2048
	assert first.writes == 1 && first.write_bytes == 1024 && first.flushes == 2
	assert first.errors == 0 && first.last_error == 0
	assert partition_status.reads == first.reads && partition_status.writes == first.writes
		&& partition_status.flushes == first.flushes
	assert partition_status.start == 4096 && partition_status.bytes == 2048 * 512
	other := second.block_status()
	assert other.disk_id == 92 && other.reads == 0 && other.writes == 0 && other.flushes == 1
	assert model.account_reads == first.read_bytes && model.account_writes == first.write_bytes
	assert model.commands == 0 // Status never submits admin commands.
}

fn test_ans_status_preserves_read_and_global_flush_prefixes() {
	mut model := anscore.model_setup(1, 2, 0)
	ans_ready = true
	mut whole := status_disk(0, -1)
	mut bytes := [8192]u8{}
	assert whole.read(unsafe { nil }, unsafe { &bytes[0] }, 0, sizeof(bytes)) == none
	partial := whole.block_status()
	assert partial.reads == 1 && partial.read_bytes == 4096 && partial.errors == 1
	assert partial.last_error == u64(errno.eio) && partial.flags == 5
	model.mode = 0
	assert whole.read(unsafe { nil }, unsafe { &bytes[0] }, 0, 512) or { -1 } == 512
	assert whole.block_status().reads == 2 && whole.block_status().errors == 1
	anscore.model_free(model)
	model = anscore.model_setup(1, 2, 0)
	whole = status_disk(0, -1)
	mut second := status_disk(1, -1)
	assert second.sync(unsafe { nil }) == none
	first_status := whole.block_status()
	second_status := second.block_status()
	assert first_status.flushes == 1 && first_status.errors == 0
	assert second_status.flushes == 0 && second_status.errors == 1
	assert second_status.last_error == u64(errno.eio) && second_status.flags == 7
	assert model.io_commands == 2
	anscore.model_free(model)
}

fn test_ans_status_counts_only_completed_commands_and_one_failed_request() {
	for step in 1 .. 4 {
		model := anscore.model_setup(1, step, 0)
		ans_ready = true
		mut part := status_disk(0, 0)
		enable_writes()
		mut bytes := [511]u8{}
		assert part.write(unsafe { nil }, unsafe { &bytes[0] }, 7, 511) == none
		assert errno.get() == errno.eio
		snapshot := part.block_status()
		assert snapshot.errors == 1 && snapshot.last_error == u64(errno.eio)
		assert snapshot.reads == if step > 1 {
			u64(1)
		} else {
			u64(0)
		}
		assert snapshot.read_bytes == if step > 1 {
			u64(1024)
		} else {
			u64(0)
		}
		assert snapshot.writes == if step > 2 {
			u64(1)
		} else {
			u64(0)
		}
		assert snapshot.write_bytes == if step > 2 {
			u64(1024)
		} else {
			u64(0)
		}
		assert snapshot.flushes == 0 && snapshot.flags == 23
		commands := model.io_commands
		assert part.write(unsafe { nil }, unsafe { &bytes[0] }, 7, 511) == none
		assert model.io_commands == commands && part.block_status().errors == 2
		anscore.model_free(model)
	}
}

fn test_ans_status_validation_eof_health_and_offline_do_not_inflate_io() {
	mut model := anscore.model_setup(1, 2, 0)
	defer { anscore.model_free(model) }
	ans_ready = true
	mut whole := status_disk(0, -1)
	mut bytes := [512]u8{}
	assert whole.read(unsafe { nil }, unsafe { &bytes[0] }, u64(whole.stat.size), 512) or { -1 } == 0
	assert whole.read(unsafe { nil }, unsafe { &bytes[0] }, u64(whole.stat.size) + 1, 512) == none
	assert whole.block_status().last_error == u64(errno.einval)
	assert whole.write(unsafe { nil }, unsafe { &bytes[0] }, 0, 512) == none
	assert whole.block_status().last_error == u64(errno.erofs)
	assert whole.block_health() == none
	failed := whole.block_status()
	assert failed.errors == 3 && failed.last_error == u64(errno.eio)
	assert failed.reads == 0 && failed.writes == 0 && failed.flushes == 0
	model.mode = 0
	_ := whole.block_health() or { panic('ANS health retry failed') }
	assert whole.block_status().errors == 3 && model.io_commands == 0
	ans_ready = false
	assert whole.block_status().flags == 7
	ans_ready = true
	anscore.model_offline_state(1)
	assert whole.block_status().flags == 7
	anscore.model_offline_state(2)
	assert whole.block_status().flags == 7
	anscore.model_offline_state(3)
	assert whole.block_status().flags == 7
	whole.ns_index = 8
	assert whole.block_status().version == 0
}
