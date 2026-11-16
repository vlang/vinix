// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.ioctl
import drm.syncobj
import errno
import file
import memory
import time
import usercopy

__global info_cases = 0
__global info_callback_fence &syncobj.DmaFence = unsafe { nil }
__global info_callback_header &ioctl.SyncFileInfo = unsafe { nil }
__global info_callback_fd = -1

fn complete_between_outputs(_ u64, _ u64) { syncobj.signal_error(info_callback_fence, -11) }
fn close_between_outputs(_ u64, _ u64) { file.close(info_callback_fd) }
fn mutate_between_outputs(_ u64, _ u64) {
	unsafe {
		info_callback_header.flags = ~u32(0)
		info_callback_header.num_fences = ~u32(0)
		info_callback_header.sync_fence_info = ~u64(0)
	}
}

fn invoke_info(number int, address u64, command u64, expected u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, number) or { panic('info descriptor') }
	defer { fd.unref() }
	mut res := fd.handle.resource
	errno.set(0)
	if expected == 0 {
		assert (res.ioctl(voidptr(fd.handle), command, voidptr(address)) or { panic('info refused: ${errno.get()}') }) == 0
	} else {
		if _ := res.ioctl(voidptr(fd.handle), command, voidptr(address)) { assert false, 'expected info errno ${expected}' }
		assert errno.get() == expected
	}
	info_cases++
}

fn prepare_info(header &ioctl.SyncFileInfo, details &ioctl.SyncFenceInfo, count u32) {
	mut h := unsafe { header }
	unsafe {
		*h = ioctl.SyncFileInfo{ status: -123, num_fences: count, sync_fence_info: u64(details) }
		C.memset(&h.name[0], 0xa5, 32)
		C.memset(details, 0xa5, sizeof(ioctl.SyncFenceInfo) * 2)
	}
	usercopy.allow(u64(header), sizeof(ioctl.SyncFileInfo))
	usercopy.allow_output(u64(header), sizeof(ioctl.SyncFileInfo))
	usercopy.allow_output(u64(details), sizeof(ioctl.SyncFenceInfo) * 2)
}

fn check_info_name(actual &u8, expected string, tail u8) {
	count := if expected.len < 31 { expected.len } else { 31 }
	for index in 0 .. count { assert unsafe { actual[index] } == expected[index] }
	assert unsafe { actual[count] } == 0
	for index in count + 1 .. 32 { assert unsafe { actual[index] } == tail }
}

fn check_info_result(header &ioctl.SyncFileInfo, details &ioctl.SyncFenceInfo, driver string, timeline string,
	context u64, seqno u64, status int, timestamp u64, detailed bool) {
	check_info_name(unsafe { &header.name[0] }, '${driver}-${timeline}${context}-${i64(seqno)}', 0xa5)
	assert header.status == status && header.num_fences == 1 && header.flags == 0 && header.pad == 0
	assert header.sync_fence_info == u64(details)
	if detailed {
		check_info_name(unsafe { &details.obj_name[0] }, timeline, 0)
		check_info_name(unsafe { &details.driver_name[0] }, driver, 0)
		assert details.status == status && details.timestamp_ns == timestamp && details.flags == 0
	}
	for index in 0 .. int(sizeof(ioctl.SyncFenceInfo)) {
		assert unsafe { (&u8(details))[int(sizeof(ioctl.SyncFenceInfo)) + index] } == 0xa5,
			'query must copy exactly one fence even when a larger capacity is supplied'
	}
}

pub fn run_sync_file_info_checks() {
	assert sizeof(ioctl.SyncFileInfo) == 56 && sizeof(ioctl.SyncFenceInfo) == 80
	assert __offsetof(ioctl.SyncFileInfo, sync_fence_info) == 48
	assert __offsetof(ioctl.SyncFenceInfo, timestamp_ns) == 72
	assert ioctl.sync_ioc_file_info == 0xc0383e04
	memory.reset()
	for _ in 0 .. 200 {
		time.reset()
		for family in 0 .. 3 {
			obj := make_object(if family == 2 { ioctl.drm_syncobj_create_signaled } else { u32(0) })
			fence := if family == 2 { current(obj) } else if family == 1 {
				remember_fence(syncobj.new_queue_fence(7, 9, syncobj.new_queue_context() or { panic('queue identity') }))
			} else { make_fence() }
			if family != 2 { syncobj.replace_fence(obj, fence) }
			driver := if family == 2 { 'stub' } else if family == 1 { 'asahi' } else { 'vinix' }
			timeline := if family == 2 { 'stub' } else if family == 1 { 'queue' } else { 'fence' }
			mut expected_status := if family == 2 { 1 } else { 0 }
			mut expected_time := if family == 2 { time.monotonic_ns() } else { u64(0) }
			number := export_object(11, obj.handle, 1)
			mut header := ioctl.SyncFileInfo{}
			mut details := [2]ioctl.SyncFenceInfo{}
			for stage in 0 .. 3 {
				if stage == 1 {
					time.advance()
					if family == 1 { syncobj.signal_error(fence, -5) } else { syncobj.signal(fence) }
					if family != 2 { expected_status = if family == 1 { -5 } else { 1 }; expected_time = time.monotonic_ns() }
				} else if stage == 2 { time.advance(); syncobj.signal_error(fence, -19); syncobj.signal(fence) }
				for capacity in [u32(0), 1, 2, ~u32(0)]! {
					prepare_info(unsafe { &header }, unsafe { &details[0] }, capacity)
					attempts := memory.attempts(); live := memory.outstanding()
					invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), 0)
					assert usercopy.reads == 1 && usercopy.writes == if capacity == 0 { 1 } else { 2 }
					assert memory.attempts() == attempts + if capacity == 0 { 0 } else { 1 }
					assert memory.outstanding() == live
					check_info_result(unsafe { &header }, unsafe { &details[0] }, driver, timeline, fence.context,
						fence.seqno, expected_status, expected_time, capacity != 0)
				}
			}
			// Validation precedes allocation/output; count-only ignores the array
			// pointer and preserves an armed allocation failure for the next query.
			for reserved in 0 .. 2 {
				prepare_info(unsafe { &header }, unsafe { &details[0] }, ~u32(0))
				if reserved == 0 { header.flags = 1 } else { header.pad = 1 }
				attempts := memory.attempts()
				invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), errno.einval)
				assert memory.attempts() == attempts && usercopy.writes == 0 && header.status == -123
			}
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 1); usercopy.inject_fault()
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), errno.efault)
			assert usercopy.writes == 0
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 0)
			header.sync_fence_info = ~u64(0); memory.fail_next()
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), 0)
			assert header.sync_fence_info == ~u64(0) && header.num_fences == 1
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), errno.enomem)
			assert usercopy.writes == 0 && header.status == -123
			// Array faults leave the header untouched. Later header faults retain
			// the successfully copied array and free the temporary owner either way.
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
			usercopy.fail_output_at(unsafe { u64(&details[0]) } + 17)
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), errno.efault)
			assert usercopy.writes == 1 && header.status == -123 && header.name[0] == 0xa5
			for index in 17 .. 80 { assert unsafe { (&u8(&details[0]))[index] } == 0xa5 }
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
			usercopy.fail_output_at(unsafe { u64(&header) } + 5)
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), errno.efault)
			assert usercopy.writes == 2 && header.status == -123 && header.name[5] == 0xa5
			assert details[0].status == expected_status && details[0].timestamp_ns == expected_time
			assert memory.outstanding() == 2
			// Null arrays fault only after allocation; count-only faults still
			// allocate nothing. A last-byte fault exercises complete prefixes.
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
			header.sync_fence_info = 0
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), errno.efault)
			assert header.status == -123 && usercopy.writes == 1
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 0)
			attempts := memory.attempts()
			usercopy.fail_output_at(unsafe { u64(&header) } + 55)
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), errno.efault)
			assert memory.attempts() == attempts && usercopy.writes == 1
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
			usercopy.fail_output_at(unsafe { u64(&details[0]) } + 79)
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), errno.efault)
			assert header.status == -123 && unsafe { (&u8(&details[0]))[79] } == 0xa5
			// Input and output may overlap. Detail bytes land first, then the
			// staged header overwrites precisely its own 56-byte range.
			mut overlap := [20]u64{}
			mut overlapping := unsafe { &ioctl.SyncFileInfo(&overlap[0]) }
			unsafe { *overlapping = ioctl.SyncFileInfo{ num_fences: 1, sync_fence_info: u64(&overlap[0]) } }
			usercopy.allow(unsafe { u64(&overlap[0]) }, sizeof(ioctl.SyncFileInfo))
			usercopy.allow_output(unsafe { u64(&overlap[0]) }, sizeof(overlap))
			invoke_info(number, unsafe { u64(&overlap[0]) }, u64(ioctl.sync_ioc_file_info), 0)
			assert overlapping.status == expected_status && overlapping.num_fences == 1
			assert unsafe { (&ioctl.SyncFenceInfo(&overlap[0])).status } == expected_status
			assert unsafe { (&ioctl.SyncFenceInfo(&overlap[0])).timestamp_ns } == expected_time
			assert memory.outstanding() == 2
			// Unknown encodings do not touch userspace; high request bits are
			// ignored like Linux's unsigned-int ioctl command argument.
			for command in [u32(0xc0383e00), 0xc0393e04, 0x80383e04, 0xc0386404]! {
				prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
				invoke_info(number, unsafe { u64(&header) }, u64(command), errno.enotty)
				assert usercopy.reads == 0 && usercopy.writes == 0
			}
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info) | (u64(0xdeadbeef) << 32), 0)
			check_info_result(unsafe { &header }, unsafe { &details[0] }, driver, timeline, fence.context,
				fence.seqno, expected_status, expected_time, true)
			// Original input remains staged even if userspace mutates it after
			// the first output. The final header restores the original pointer.
			prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
			info_callback_header = unsafe { &header }; usercopy.after_next_output(mutate_between_outputs)
			invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), 0)
			check_info_result(unsafe { &header }, unsafe { &details[0] }, driver, timeline, fence.context,
				fence.seqno, expected_status, expected_time, true)
			info_callback_header = unsafe { nil }
			file.close(number)
		}
		// A completion between array/header writes cannot rewrite the already
		// sampled status. Closing the last installed FD is protected by lookup.
		race_obj := make_object(0); race_fence := make_fence(); syncobj.replace_fence(race_obj, race_fence)
		race_fd := export_object(11, race_obj.handle, 1)
		mut header := ioctl.SyncFileInfo{}; mut details := [2]ioctl.SyncFenceInfo{}
		// A prepared error is invisible until signaled. Namespace replacement
		// and removal cannot retarget the already exported leaf.
		mut pending := unsafe { race_fence }
		pending.error = -7
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
		invoke_info(race_fd, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), 0)
		assert header.status == 0 && details[0].timestamp_ns == 0
		syncobj.replace_fence(race_obj, make_fence())
		assert syncobj.destroy(11, race_obj.handle)
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
		info_callback_fence = race_fence; usercopy.after_next_output(complete_between_outputs)
		invoke_info(race_fd, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), 0)
		assert header.status == 0 && details[0].status == 0 && details[0].timestamp_ns == 0
		prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
		info_callback_fd = race_fd; usercopy.after_next_output(close_between_outputs)
		invoke_info(race_fd, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), 0)
		assert header.status == -11 && details[0].status == -11 && details[0].timestamp_ns == time.monotonic_ns()
		assert file.outstanding() == 0 && memory.outstanding() == 0
		info_callback_fence = unsafe { nil }; info_callback_fd = -1
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	}
	// Formatting covers both unsigned context and signed sequence boundaries,
	// including snprintf-style truncation and preservation after the first NUL.
	for queued in [false, true]! {
		obj := make_object(0)
		for context in [u64(0), 1, u64(1) << 63, ~u64(0)]! {
			for seqno in [u64(0), 1, u64(1) << 63, ~u64(0)]! {
				fence := if queued { remember_fence(syncobj.new_queue_fence(context, seqno,
					syncobj.new_queue_context() or { panic('format queue') })) } else { remember_fence(syncobj.new_fence(context, seqno)) }
				syncobj.replace_fence(obj, fence)
				number := export_object(11, obj.handle, 1)
				mut header := ioctl.SyncFileInfo{}; mut details := [2]ioctl.SyncFenceInfo{}
				prepare_info(unsafe { &header }, unsafe { &details[0] }, 1)
				invoke_info(number, unsafe { u64(&header) }, u64(ioctl.sync_ioc_file_info), 0)
				check_info_result(unsafe { &header }, unsafe { &details[0] }, if queued { 'asahi' } else { 'vinix' },
					if queued { 'queue' } else { 'fence' }, context, seqno, 0, 0, true)
				file.close(number)
			}
		}
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	}
	println('DRM sync-file info: ${info_cases} cases; 56/80-byte UAPI, count/detail capacities, pending/success/error and first timestamps, stub/queue/generic names, zeroed records, signed/truncated names, copy/OOM cleanup, staged inputs and last-FD close passed')
}
