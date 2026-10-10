// SPDX-License-Identifier: GPL-2.0-or-later
// Copied only into an opt-in isolated kernel, never an ordinary build.
module ans

import apple.ans.anscore
import memory
import resource
import stat

fn health_fixture_require(condition bool) {
	if !condition { panic('ANS health kernel oracle failed') }
}

fn health_fixture_snapshot(output &memory.HeapClass) int {
	classes := memory.heap_classes()
	health_fixture_require(classes.len <= 32)
	for i, class in classes {
		unsafe { output[i] = class }
	}
	count := classes.len
	unsafe { classes.free() }
	return count
}

fn health_fixture_run() {
	model := anscore.model_setup(0, 0, 0x80)
	ans_ready = true
	mut disk := AnsBlock{ stat: stat.Stat{ rdev: 91 }, ns_index: 1 }
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
		health_fixture_require(report.identify[511] == u8(511 * 17 + 6) && report.data[511] == u8(511 * 17 + 2))
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
	// No hardware owns this host model; retire it before native ANS probing.
	ans_ready = false
	anscore.model_free(model)
	C.kprintf(c'ANS HEALTH MODEL PASSED: 200 queries, no retained slab/large allocations\n')
}
