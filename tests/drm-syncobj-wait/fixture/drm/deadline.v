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

__global deadline_cases = 0
__global deadline_close_number = -1

fn deadline_close_lookup() { file.close(deadline_close_number) }

fn invoke_deadline(number int, command u64, address u64, expected u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, number) or { panic('deadline descriptor') }
	defer { fd.unref() }
	mut res := fd.handle.resource
	errno.set(0)
	if expected == 0 {
		assert (res.ioctl(voidptr(fd.handle), command, voidptr(address)) or { panic('deadline refused: ${errno.get()}') }) == 0
	} else {
		if _ := res.ioctl(voidptr(fd.handle), command, voidptr(address)) { assert false, 'deadline errno ${expected}' }
		assert errno.get() == expected
	}
	deadline_cases++
}

fn assert_same_deadline_leaf(fence &syncobj.DmaFence, before syncobj.FenceSnapshot) {
	after := syncobj.snapshot(fence)
	assert after.status == before.status && after.timestamp_ns == before.timestamp_ns
	assert after.context == before.context && after.seqno == before.seqno && after.kind == before.kind
}

pub fn run_sync_file_deadline_checks() {
	assert sizeof(ioctl.SyncSetDeadline) == 16 && __offsetof(ioctl.SyncSetDeadline, pad) == 8
	assert ioctl.sync_ioc_set_deadline == 0x40103e05
	memory.reset()
	check_binary_deadlines()
	check_timeline_deadlines()
	check_nested_deadlines()
	println('DRM WAIT deadlines: initial readiness, timeout and validation order, settled captures, future submissions, signed minimum and 2048 nested links passed')
	for _ in 0 .. 200 {
		time.reset()
		for family in 0 .. 3 {
			obj := make_object(if family == 2 { ioctl.drm_syncobj_create_signaled } else { u32(0) })
			fence := if family == 2 { current(obj) } else if family == 1 {
				remember_fence(syncobj.new_queue_fence(7, 9, syncobj.new_queue_context() or { panic('deadline queue') }))
			} else { make_fence() }
			if family != 2 { syncobj.replace_fence(obj, fence) }
			number := export_object(11, obj.handle, 1)
			mut request := ioctl.SyncSetDeadline{}
			for stage in 0 .. 3 {
				if stage == 1 { time.advance(); syncobj.signal_error(fence, -5) }
				if stage == 2 { time.advance(); syncobj.signal(fence); syncobj.signal_error(fence, -19) }
				before := syncobj.snapshot(fence)
				readiness := poll_descriptor(number)
				generation := descriptor_generation(number)
				attempts := memory.attempts(); live := memory.outstanding()
				// Linux accepts the complete u64 bit-pattern range, including
				// past/zero values and ns_to_ktime's signed high half.
				for value in [u64(0), 1, (u64(1) << 63) - 1, u64(1) << 63, ~u64(0)]! {
					request = ioctl.SyncSetDeadline{ deadline_ns: value }
					usercopy.allow(unsafe { u64(&request) }, sizeof(request))
					invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline), unsafe { u64(&request) }, 0)
					assert request.deadline_ns == value && request.pad == 0
					assert usercopy.reads == 1 && usercopy.writes == 0
					assert_same_deadline_leaf(fence, before)
					assert poll_descriptor(number) == readiness && descriptor_generation(number) == generation
				}
				assert memory.attempts() == attempts && memory.outstanding() == live
				if family == 1 { expect_fence_deadline(fence, i64(u64(1) << 63)) }
				else { expect_no_fence_deadline(fence) }
			}
			for reserved in [u64(1), u64(1) << 63, ~u64(0)]! {
				request = ioctl.SyncSetDeadline{ deadline_ns: ~u64(0), pad: reserved }
				usercopy.allow(unsafe { u64(&request) }, sizeof(request))
				invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline), unsafe { u64(&request) }, errno.einval)
				assert request.pad == reserved && usercopy.reads == 1 && usercopy.writes == 0
			}
			// A short header must fail even when its available padding bytes
			// already contain an invalid value: copy faults precede pad checks.
			for size in 0 .. 16 {
				request = ioctl.SyncSetDeadline{ deadline_ns: 1, pad: ~u64(0) }
				usercopy.allow(unsafe { u64(&request) }, u64(size))
				invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline), unsafe { u64(&request) }, errno.efault)
				assert usercopy.reads == 1 && usercopy.writes == 0
			}
			usercopy.allow(0, 16)
			invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline), 0, errno.efault)
			usercopy.allow(1, 16)
			invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline), ~u64(0) - 7, errno.efault)
			request = ioctl.SyncSetDeadline{}
			usercopy.allow(unsafe { u64(&request) }, sizeof(request)); usercopy.inject_fault()
			invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline), unsafe { u64(&request) }, errno.efault)
			for command in [u32(0x40103e00), 0x40113e05, 0x80103e05, 0xc0103e05, 0x40106405]! {
				usercopy.allow(unsafe { u64(&request) }, sizeof(request))
				invoke_deadline(number, u64(command), unsafe { u64(&request) }, errno.enotty)
				assert usercopy.reads == 0 && usercopy.writes == 0
			}
			usercopy.allow(unsafe { u64(&request) }, sizeof(request))
			invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline) | (u64(0xdeadbeef) << 32), unsafe { u64(&request) }, 0)
			assert usercopy.reads == 1 && usercopy.writes == 0
			// Hint forwarding does not need scratch storage.
			usercopy.allow(unsafe { u64(&request) }, sizeof(request)); memory.fail_next()
			attempts := memory.attempts()
			invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline), unsafe { u64(&request) }, 0)
			assert memory.attempts() == attempts && memory.malloc_packed_fallible(1) == unsafe { nil }
			file.close(number)
		}
		// Only sync-file descriptors accept the command. Opaque descriptors do
		// not copy the request even when it points to an invalid address.
		obj := make_object(0); fence := make_deadline_fence(); syncobj.replace_fence(obj, fence)
		opaque := export_object(11, obj.handle, 0)
		usercopy.allow(0, 0)
		invoke_deadline(opaque, u64(ioctl.sync_ioc_set_deadline), 0, errno.enotty)
		assert usercopy.reads == 0 && usercopy.writes == 0
		file.close(opaque)
		// Source teardown cannot change the exported leaf. The lookup reference
		// protects a final descriptor close before either success or EFAULT.
		number := export_object(11, obj.handle, 1)
		replacement := make_deadline_fence()
		syncobj.replace_fence(obj, replacement); syncobj.destroy_owner(11)
		mut request := ioctl.SyncSetDeadline{}
		usercopy.allow(unsafe { u64(&request) }, sizeof(request))
		invoke_deadline(number, u64(ioctl.sync_ioc_set_deadline), unsafe { u64(&request) }, 0)
		assert !syncobj.is_signaled(fence)
		expect_fence_deadline(fence, 0)
		duplicate := file.duplicate(number)
		for fdnum in [number, duplicate]! {
			deadline_close_number = fdnum
			request.deadline_ns = if fdnum == duplicate { u64(1) << 63 } else { ~u64(0) }
			usercopy.allow(unsafe { u64(&request) }, sizeof(request))
			if fdnum == duplicate { usercopy.inject_fault() }
			file.when_lookup(deadline_close_lookup)
			invoke_deadline(fdnum, u64(ioctl.sync_ioc_set_deadline), unsafe { u64(&request) }, if fdnum == duplicate { errno.efault } else { u64(0) })
		}
		expect_fence_deadline(fence, -1)
		expect_no_fence_deadline(replacement)
		deadline_close_number = -1
		assert file.outstanding() == 0 && memory.outstanding() == 0
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	}
	println('DRM sync-file deadline: ${deadline_cases} cases; exact 16-byte write-only UAPI, full deadline range, pad/copy precedence, no allocation/output/readiness effects, typed dispatch, stable leaves and retained final-FD lookup passed')
}
