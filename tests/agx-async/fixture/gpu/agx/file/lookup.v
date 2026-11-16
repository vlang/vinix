// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.syncobj
import gpu.agx.gpu
import memory

fn check_missing_queue_submission_failures() {
	gpu.reset()
	mut file := new_file()
	manager := gpu.get_global_manager() or { panic('manager') }
	mut bytes := [8192]u8{init: 0xa5}
	mut object := gem.GemObject{ size: sizeof(bytes), virt_addr: unsafe { u64(&bytes) } }
	file.objects = Objects{ object: unsafe { &object } }
	for _ in 0 .. 200 {
		for queue in [u32(0), 3, 64, ~u32(0)]! {
			assert submit(mut file, queue, false, unsafe { nil }, unsafe { nil }, true) == -2, 'missing queue must return ENOENT'
		}
		memory.fail_at(0)
		assert submit(mut file, 3, false, unsafe { nil }, unsafe { nil }, true) == -2
		memory.fail_at(-1)
		// A present queue with invalid internal VM state remains EINVAL.
		file.queues[0] = LogicalQueue{ id: 1, vm_id: 0 }
		assert submit(mut file, 1, false, unsafe { nil }, unsafe { nil }, true) == -22
		file.queues[0] = LogicalQueue{ id: 1, vm_id: 64 }
		assert submit(mut file, 1, false, unsafe { nil }, unsafe { nil }, true) == -22
		file.queues[0] = LogicalQueue{ id: 1 }
		assert_drained(file)
		file.lock.acquire(); file.lock.release()
		assert manager.published.len == 0 && object.references == 1
		for value in bytes { assert value == 0xa5 }
	}
	file.objects = Objects{}
	println('AGX missing queue: 1400 ioctl checks; ENOENT for absent queues before allocation, EINVAL for present invalid VM state, returned storage, unchanged result bytes and zero published work passed')
}

fn check_missing_syncobj_submission_failures() {
	gpu.reset()
	mut file := new_file()
	manager := gpu.get_global_manager() or { panic('manager') }
	empty := output()
	missing := syncobj.SyncObj{ handle: ~u32(0) }
	mut bytes := [8192]u8{init: 0xa5}
	mut object := gem.GemObject{ size: sizeof(bytes), virt_addr: unsafe { u64(&bytes) } }
	file.objects = Objects{ object: unsafe { &object } }
	for _ in 0 .. 200 {
		assert submit(mut file, 1, false, unsafe { &missing }, empty, true) == -2
		assert submit(mut file, 1, false, unsafe { nil }, unsafe { &missing }, true) == -2
		assert submit(mut file, 1, false, empty, empty, true) == -22
		// Existing command-storage allocation still precedes sync lookup.
		memory.fail_at(0)
		assert submit(mut file, 1, false, unsafe { &missing }, empty, true) == -12
		memory.fail_at(-1)
		assert_drained(file)
		file.lock.acquire(); file.lock.release()
		assert manager.published.len == 0 && object.references == 1
		if _ := syncobj.get_fence(empty) { assert false, 'failed staging published an output fence' }
		for value in bytes { assert value == 0xa5 }
	}
	file.objects = Objects{}
	println('AGX missing syncobj: 800 ioctl checks; ENOENT input/output lookup, EINVAL empty input, allocation precedence, returned request storage, unchanged result bytes/output fences and zero published jobs passed')
}
