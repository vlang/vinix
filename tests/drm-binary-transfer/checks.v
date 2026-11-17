// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import memory
import proc
import sched
import time
import klock

__global bt_source &syncobj.SyncObj = unsafe { nil }
__global bt_destination &syncobj.SyncObj = unsafe { nil }
__global bt_leaf &syncobj.DmaFence = unsafe { nil }
__global bt_new_source &syncobj.SyncObj = unsafe { nil }
__global bt_new_destination &syncobj.SyncObj = unsafe { nil }
__global bt_mode = 0
__global bt_lock_count = 0
__global bt_chained = false

fn bt_publish() {
	if bt_chained { tw_chain(bt_source, bt_leaf, 7) }
	else { syncobj.replace_fence(bt_source, bt_leaf) }
}

fn bt_action(step u32) {
	if step != 1 { return }
	match bt_mode {
		0 { bt_publish() }
		1 {
			assert syncobj.destroy(11, bt_source.handle)
			bt_new_source = make_object(ioctl.drm_syncobj_create_signaled)
			assert bt_new_source.handle == bt_source.handle
			assert syncobj.destroy(11, bt_destination.handle)
			bt_new_destination = make_object(ioctl.drm_syncobj_create_signaled)
			assert bt_new_destination.handle == bt_destination.handle
			bt_publish()
		}
		2 { proc.private_signal(false) }
		3 { proc.shared_signal() }
		4 { proc.exit_thread() }
		5 { time.advance_by(4_999_999_000) }
		6 { time.advance_by(4_999_999_000); proc.private_signal(false); bt_publish() }
		7 { proc.private_signal(true); bt_publish() }
		else {}
	}
}

fn bt_gap() {
	bt_lock_count--
	if bt_lock_count > 0 { klock.before_once(unsafe { &bt_source.lock }, bt_gap) }
	else {
		bt_publish()
		syncobj.replace_fence(bt_source, unsafe { nil })
	}
}

fn bt_retire() {
	for index in 0 .. wait_fixture_object_count {
		assert syncobj.timeline_wait_pending_for_checks(wait_fixture_objects[index]) == 0, 'transfer capture must detach before returning'
	}
	for index in 0 .. wait_fixture_fence_count { syncobj.signal(wait_fixture_fences[index]) }
	clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	bt_source = unsafe { nil }; bt_destination = unsafe { nil }; bt_leaf = unsafe { nil }
	bt_new_source = unsafe { nil }; bt_new_destination = unsafe { nil }
}

fn bt_request(point u64, flags u32) ioctl.DrmSyncobjTransfer {
	return ioctl.DrmSyncobjTransfer{src_handle: bt_source.handle, dst_handle: bt_destination.handle, src_point: point, flags: flags}
}

pub fn run_binary_transfer_checks() {
	memory.reset(); memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	assert sizeof(ioctl.DrmSyncobjTransfer) == 32
	assert __offsetof(ioctl.DrmSyncobjTransfer, dst_handle) == 4 && __offsetof(ioctl.DrmSyncobjTransfer, src_point) == 8
	assert __offsetof(ioctl.DrmSyncobjTransfer, dst_point) == 16 && __offsetof(ioctl.DrmSyncobjTransfer, flags) == 24 && __offsetof(ioctl.DrmSyncobjTransfer, pad) == 28
	layout := common_ioctl_layout(ioctl.drm_ioctl_syncobj_transfer) or { panic('TRANSFER layout') }
	assert layout.size == 32 && layout.direction == ioctl_read | ioctl_write
	assert u32(3) << 30 | u32(32) << 16 | u32(`d`) << 8 | ioctl.drm_ioctl_syncobj_transfer == 0xc02064cc
	mut cases := 0
	for _ in 0 .. 100 {
		proc.reset(); sched.reset(unsafe { nil })
		bt_source = make_object(0); bt_destination = make_object(0); bt_leaf = make_fence()
		old := make_fence(); syncobj.replace_fence(bt_destination, old)
		// Header pad, destination name, source name, then flags precedence.
		for stage in 0 .. 5 {
			mut request := bt_request(0, 16)
			if stage < 2 { request.dst_handle = ~u32(0) }
			if stage < 3 { request.src_handle = ~u32(0) }
			if stage == 0 { request.pad = 1 }
			if stage == 4 { request.flags = 0 }
			before := memory.attempts()
			assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == if stage in [0, 3, 4]! { -22 } else { -2 }
			assert current(bt_destination) == old && memory.attempts() == before
			cases++
		}
		for flags in [u32(0), ioctl.drm_syncobj_wait_for_submit]! {
			syncobj.replace_fence(bt_source, bt_leaf)
			mut request := bt_request(0, flags)
			mut capture := syncobj.FenceCapture{}
			syncobj.replace_fence(bt_destination, unsafe { nil })
			assert syncobj.prepare_capture(bt_destination, unsafe { &capture }, true)
			before := memory.attempts()
			assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == 0
			assert memory.attempts() == before && current(bt_destination) == bt_leaf && sched.polls == 0
			assert !syncobj.is_signaled(bt_leaf), 'transfer must not wait for completion'
			assert (syncobj.captured_fence(unsafe { &capture }) or { panic('publication') }) == bt_leaf
			syncobj.release_capture(unsafe { &capture })
			syncobj.replace_fence(bt_source, old)
			assert current(bt_destination) == bt_leaf, 'source replacement must not retarget destination'
			cases++
		}
		// Self-transfer retains its head and its pointer; a future point is not
		// accepted without SUBMIT even when the destination already has a fence.
		syncobj.replace_fence(bt_source, bt_leaf)
		mut request := bt_request(0, 0); request.dst_handle = bt_source.handle
		assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == 0 && current(bt_source) == bt_leaf
		request = bt_request(1, 0)
		assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == -22
		request = bt_request(0, 0); request.dst_point = 1
		assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == 0
		assert syncobj.chain_contained(remember_fence(current(bt_destination))) == bt_leaf
		assert ioctl_syncobj_transfer(unsafe { nil }, unsafe { &request }) == -14
		assert ioctl_syncobj_transfer(voidptr(11), unsafe { nil }) == -14
		bt_retire(); cases += 5
	}
	// Chains remain cumulative when copied; retired positive points use the
	// permanent completion, while point zero preserves the current root.
	for point in [u64(0), 1, 2, 7, ~u64(0)]! {
		proc.reset(); sched.reset(unsafe { nil })
		bt_source = make_object(0); bt_destination = make_object(0); bt_leaf = make_fence()
		prefix := make_fence(); syncobj.signal_error(prefix, -5); tw_chain(bt_source, prefix, 1)
		head := tw_chain(bt_source, bt_leaf, 7)
		mut request := bt_request(point, 0)
		code := ioctl_syncobj_transfer(voidptr(11), unsafe { &request })
		assert code == if point == ~u64(0) { -22 } else { 0 }
		if code == 0 {
			assert current(bt_destination) == if point == 1 { syncobj.shared_timeline_stub() } else { head }
			assert syncobj.is_signaled(current(bt_destination)) == (point == 1)
		}
		bt_retire(); cases++
	}
	for chained in [false, true]! { for mode in 0 .. 8 {
		proc.reset(); sched.reset(bt_action); bt_mode = mode; bt_chained = chained
		bt_source = make_object(0); bt_destination = make_object(0); bt_leaf = make_fence()
		old := make_fence(); syncobj.replace_fence(bt_destination, old)
		mut request := bt_request(if chained { u64(7) } else { u64(0) }, ioctl.drm_syncobj_wait_for_submit)
		before := memory.attempts()
		code := ioctl_syncobj_transfer(voidptr(11), unsafe { &request })
		assert code == if mode in [2, 3, 4]! { -512 } else if mode == 5 { -62 } else { 0 }
		assert sched.polls == 1
		assert syncobj.timeline_wait_pending_for_checks(bt_source) == 0, 'transfer capture must detach before returning'
		if code == 0 {
			assert !syncobj.is_signaled(current(bt_destination)), 'availability transfer must leave pending work pending'
			if chained { assert syncobj.chain_contained(current(bt_destination)) == bt_leaf }
			else { assert current(bt_destination) == bt_leaf }
			if mode == 1 {
				assert current(bt_new_destination) != current(bt_destination)
				assert current(bt_new_source) != current(bt_source)
			}
		} else { assert current(bt_destination) == old; bt_publish() }
		if !chained && mode != 1 { assert memory.attempts() == before, 'lookup/capture/transfer must allocate nothing' }
		bt_retire(); cases++
	} }
	// A transient publication before the arm pass is missed. The later source
	// publication is captured without leaking the temporary stack node.
	proc.reset(); sched.reset(bt_action); bt_mode = 0; bt_chained = true
	bt_source = make_object(0); bt_destination = make_object(0); bt_leaf = make_fence()
	bt_lock_count = 3; klock.before_once(unsafe { &bt_source.lock }, bt_gap)
	mut request := bt_request(7, ioctl.drm_syncobj_wait_for_submit)
	assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == 0 && sched.polls == 1
	bt_retire()
	println('DRM binary TRANSFER: ${cases} counted checks; 32-byte UAPI, lookup/error precedence, zero/positive/retired source points, pending/error chains, destination publication, self-copy, source/destination name reuse, 5s timeout, signals and stack capture cleanup pass. Timeline destination path checked separately.')
}

pub fn run_binary_transfer_trace() {
	memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
	for state in 0 .. 7 { for point in [u64(0), 1, 2, 3, u64(1) << 63, ~u64(0)]! {
		for flags := u32(0); flags < 16; flags++ { for missing in 0 .. 4 { for pad in 0 .. 2 { for same in [false, true]! {
			memory.reset(); proc.reset(); sched.reset(bt_action); bt_mode = 5; bt_chained = false
			bt_source = tw_trace_object(state); bt_destination = if same { bt_source } else { make_object(0) }
			mut request := bt_request(point, flags)
			if missing & 1 != 0 { request.src_handle = ~u32(0) }
			if missing & 2 != 0 { request.dst_handle = ~u32(0) }
			request.pad = u32(pad)
			code := ioctl_syncobj_transfer(voidptr(11), unsafe { &request })
			fence := syncobj.get_fence(bt_destination) or { unsafe { nil } }
			info := syncobj.snapshot(fence)
			println('${code} ${int(fence != unsafe { nil })} ${info.status} ${info.seqno}')
			bt_retire()
		} } } }
	} }
}

pub fn measure_binary_transfer_owners() {
	$if macos {
		memory.configure_metadata(sizeof(syncobj.SyncObj), sizeof(syncobj.DmaFence))
		proc.reset(); sched.reset(unsafe { nil })
		bt_source = make_object(0); bt_destination = make_object(0); bt_leaf = make_fence()
		for mode in 0 .. 3 {
			for batch in 0 .. 4 {
				before_blocks, before_bytes := live_record_heap()
				for _ in 0 .. 1000 {
					proc.reset(); sched.reset(bt_action); bt_mode = if mode == 1 { 5 } else { 2 }; bt_chained = false
					syncobj.replace_fence(bt_source, if mode == 0 { bt_leaf } else { unsafe { nil } })
					mut request := bt_request(0, ioctl.drm_syncobj_wait_for_submit)
					before := memory.attempts()
					assert ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == if mode == 0 { 0 } else if mode == 1 { -62 } else { -512 }
					assert memory.attempts() == before && memory.outstanding() == 0 && memory.live_bytes() == 0
					assert syncobj.timeline_wait_pending_for_checks(bt_source) == 0
				}
				after_blocks, after_bytes := live_record_heap()
				if batch != 0 {
					assert before_blocks == after_blocks && before_bytes == after_bytes
					println('binary-transfer mode=${mode} batch=${batch} cycles=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
				}
			}
		}
		bt_retire()
	} $else { panic('malloc-zone measurement requires macOS') }
}
