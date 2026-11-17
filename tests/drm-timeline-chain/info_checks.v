// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import memory
import usercopy

__global retiring_chain_leaf &syncobj.DmaFence = unsafe { nil }

fn retire_chain_during_allocation() { syncobj.signal_error(retiring_chain_leaf, -5) }

pub fn run_chain_info_checks() {
	// Direct production handler calls isolate the two unwrap passes from FD
	// fixture metadata retention; descriptor ownership is covered separately.
	memory.reset()
	for fault in 0 .. 4 {
		mut obj := syncobj.SyncObj{}
		mut first := syncobj.DmaFence{context: 1, seqno: 1}
		mut second := syncobj.DmaFence{context: 2, seqno: 1}
		n1 := syncobj.reserve_chain() or { panic('reserve') }
		n2 := syncobj.reserve_chain() or { panic('reserve') }
		assert syncobj.add_chain_point(&obj, n1, &first, 10)
		assert syncobj.add_chain_point(&obj, n2, &second, 20)
		mut header := ioctl.SyncFileInfo{}
		mut details := [2]ioctl.SyncFenceInfo{}
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 0)
		assert sync_file_info_ioctl(n2, unsafe { u64(&header) }) == 0
		assert header.num_fences == 2 && header.status == 0 && usercopy.writes == 1
		check_info_name(unsafe { &header.name[0] }, 'dma_fence_chain-unbound${n2.context}-20', 0xa5)
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
		attempts := memory.attempts()
		assert sync_file_info_ioctl(n2, unsafe { u64(&header) }) == -22
		assert memory.attempts() == attempts && usercopy.writes == 0
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 2)
		memory.fail_next()
		assert sync_file_info_ioctl(n2, unsafe { u64(&header) }) == -12 && usercopy.writes == 0
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 2)
		assert sync_file_info_ioctl(n2, unsafe { u64(&header) }) == 0
		assert header.num_fences == 2 && header.status == 0
		for detail in details { assert detail.status == 0 && detail.timestamp_ns == 0 && detail.flags == 0 }
		// Retirement between the count and fill passes shrinks num_fences but
		// still copies the FIRST pass's zero-filled buffer, including its tail.
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 2)
		retiring_chain_leaf = &first
		memory.after_next_allocation(retire_chain_during_allocation)
		if fault == 1 { usercopy.fail_output_at(unsafe { u64(&details[1]) } + 7) }
		if fault == 2 { usercopy.fail_output_at(unsafe { u64(&header) }) }
		if fault == 3 {
			usercopy.allow(unsafe { u64(&header) }, sizeof(header))
			usercopy.allow_output(unsafe { u64(&header) }, sizeof(header))
			usercopy.allow_output(unsafe { u64(&details[0]) }, sizeof(ioctl.SyncFenceInfo))
		}
		code := sync_file_info_ioctl(n2, unsafe { u64(&header) })
		assert code == if fault == 0 { 0 } else { -14 }
		assert memory.outstanding() == 2, 'only two retained chain nodes remain'
		if fault == 0 {
			assert header.num_fences == 1 && header.status == 0
			for index in 0 .. int(sizeof(ioctl.SyncFenceInfo)) { assert unsafe { (&u8(&details[1]))[index] } == 0 }
		}
		syncobj.signal_error(&second, -19)
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 0)
		assert sync_file_info_ioctl(n2, unsafe { u64(&header) }) == 0 && header.status == 1
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 2)
		assert sync_file_info_ioctl(n2, unsafe { u64(&header) }) == 0
		assert header.num_fences == 1 && header.status == -19 && details[0].status == -19
		assert details[0].timestamp_ns != 0 && details[0].flags == 0
		// Fixture-only retirement after all synchronous handlers and child
		// callbacks return. Production published metadata remains retained.
		assert syncobj.is_signaled(n1) && syncobj.is_signaled(n2)
		memory.free(voidptr(n2)); memory.free(voidptr(n1))
		memory.reset()
	}
	retiring_chain_leaf = unsafe { nil }
	println('Sync-file chains: count/capacity/OOM, head-first leaf records, root success versus leaf error, inter-pass retirement, original-sized zero tail and tail/header/short-span copy faults pass.')
}
