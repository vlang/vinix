// SPDX-License-Identifier: GPL-2.0-or-later
// Copied only into an opt-in isolated kernel, never an ordinary build.
module ans

import apple.ans.anscore
import errno
import memory
import resource
import stat

fn C.vinix_stack_alloc(u64) voidptr

fn health_fixture_require(condition bool) {
	if !condition { panic('ANS health kernel oracle failed') }
}

fn health_fixture_snapshot(output &memory.HeapClass) int {
	classes := memory.heap_classes()
	health_fixture_require(classes.len <= 32)
	for i, class in classes {
		unsafe {
			output[i] = class
		}
	}
	count := classes.len
	unsafe { classes.free() }
	return count
}

fn status_fixture_cycle(mut whole AnsBlock, mut part AnsBlock) {
	mut bytes := [513]u8{}
	bytes[0] = 0x73
	bytes[512] = 0x94
	health_fixture_require((part.read(unsafe { nil }, unsafe { &bytes[1] }, 7, 511) or { -1 }) == 511)
	health_fixture_require(bytes[0] == 0x73 && bytes[512] == 0x94 && bytes[1] == u8(7 * 17 + 2))
	bytes[1] = 0x31
	bytes[511] = 0xc7
	health_fixture_require((part.write(unsafe { nil }, unsafe { &bytes[1] }, 7, 511) or { -1 }) == 511)
	part.sync(unsafe { nil }) or { panic('ANS status fixture flush failed') }
	if _ := whole.write(unsafe { nil }, unsafe { &bytes[1] }, 0, 511) {
		panic('ANS status fixture accepted raw write')
	}
	health_fixture_require(errno.get() == errno.erofs)
	mut box := resource.Resource(unsafe { &part })
	status := resource.block_status(mut box) or { panic('ANS status fixture query failed') }
	health_fixture_require(status.version == 1 && status.flags == 20 && status.disk_id == 91)
	health_fixture_require(status.bytes == 2048 * 512 && status.start == 4096
		&& status.sector == 512)
	health_fixture_require(status.last_error == errno.erofs)
}

fn status_fixture_run() {
	anscore.set_namespace_id(0, 91)
	anscore.set_namespace_id(1, 92)
	anscore.model_enable_writes()
	mut whole := unsafe { &AnsBlock(C.vinix_stack_alloc(sizeof(AnsBlock))) }
	mut part := unsafe { &AnsBlock(C.vinix_stack_alloc(sizeof(AnsBlock))) }
	unsafe {
		*whole = AnsBlock{
			stat:     stat.Stat{
				rdev:    91
				size:    4096 * 512
				blksize: 512
			}
			ns_index: 0
		}
	}
	unsafe {
		*part = AnsBlock{
			stat:      stat.Stat{
				rdev:    150
				size:    2048 * 512
				blksize: 512
			}
			ns_index:  0
			partition: 0
			offset:    4096
		}
	}
	mut second := AnsBlock{
		stat:     stat.Stat{
			rdev:    92
			size:    4096 * 512
			blksize: 512
		}
		ns_index: 1
	}
	// Explicit stack slots prevent V's mut-argument promotion. Neither resource
	// escapes this synchronous fixture.
	for _ in 0 .. 12 {
		status_fixture_cycle(mut whole, mut part)
	}
	initial := whole.block_status()
	other := second.block_status()
	mut before := [32]memory.HeapClass{}
	count := health_fixture_snapshot(unsafe { &before[0] })
	large := memory.heap_big_pages()
	for _ in 0 .. 200 {
		status_fixture_cycle(mut whole, mut part)
	}
	final_status := whole.block_status()
	partition_status := part.block_status()
	health_fixture_require(final_status.flags == 5 && final_status.reads == initial.reads + 400)
	health_fixture_require(final_status.read_bytes == initial.read_bytes + 200 * 2048)
	health_fixture_require(final_status.writes == initial.writes + 200
		&& final_status.write_bytes == initial.write_bytes + 200 * 1024)
	health_fixture_require(final_status.flushes == initial.flushes + 400
		&& second.block_status().flushes == other.flushes + 200)
	health_fixture_require(final_status.errors == initial.errors + 200
		&& partition_status.errors == final_status.errors)
	health_fixture_require(partition_status.reads == final_status.reads
		&& partition_status.writes == final_status.writes)
	mut after := [32]memory.HeapClass{}
	health_fixture_require(health_fixture_snapshot(unsafe { &after[0] }) == count)
	health_fixture_require(memory.heap_big_pages() == large)
	for i in 0 .. count {
		C.kprintf(c'ANS STATUS RETAIN size=%llu delta=%lld\n', before[i].size,
			i64(after[i].live) - i64(before[i].live))
		health_fixture_require(before[i].size == after[i].size && before[i].live == after[i].live)
	}
	ans_ready = false
	health_fixture_require(part.block_status().flags == 23)
	C.kprintf(c'ANS STATUS MODEL PASSED: 200 read/write/flush/error cycles, no retained slab/large allocations\n')
}

fn health_fixture_run() {
	model := anscore.model_setup(0, 0, 0x80)
	ans_ready = true
	mut disk := AnsBlock{
		stat:     stat.Stat{
			rdev: 91
		}
		ns_index: 1
	}
	mut box := resource.Resource(unsafe { &disk })
	for _ in 0 .. 12 {
		report := resource.block_health(mut box) or { panic('ANS health fixture warmup failed') }
		health_fixture_require(report.version == 1 && report.protocol == 2 && report.flags == 31)
	}
	mut before := [32]memory.HeapClass{}
	count := health_fixture_snapshot(unsafe { &before[0] })
	large := memory.heap_big_pages()
	for _ in 0 .. 200 {
		report := resource.block_health(mut box) or { panic('ANS health fixture query failed') }
		health_fixture_require(report.disk_id == 91 && report.data[0] == 0x80)
		health_fixture_require(report.identify[511] == u8(511 * 17 + 6)
			&& report.data[511] == u8(511 * 17 + 2))
	}
	mut after := [32]memory.HeapClass{}
	health_fixture_require(health_fixture_snapshot(unsafe { &after[0] }) == count)
	health_fixture_require(memory.heap_big_pages() == large)
	for i in 0 .. count {
		C.kprintf(c'ANS HEALTH RETAIN size=%llu delta=%lld\n', before[i].size,
			i64(after[i].live) - i64(before[i].live))
		health_fixture_require(before[i].size == after[i].size && before[i].live == after[i].live)
	}
	health_fixture_require(model.commands == 424 && model.pre == 424 && model.post == 424)
	status_fixture_run()
	health_fixture_require(model.commands == 424 && model.io_commands == 212 * 6)
	health_fixture_require(model.write_first == 2 && model.write_last == u8(511 * 17 + 2))
	health_fixture_require(model.write_at_7 == 0x31 && model.write_at_517 == 0xc7)
	// No hardware owns this host model; retire it before native ANS probing.
	ans_ready = false
	anscore.model_free(model)
	C.kprintf(c'ANS HEALTH MODEL PASSED: 200 queries, no retained slab/large allocations\n')
}
