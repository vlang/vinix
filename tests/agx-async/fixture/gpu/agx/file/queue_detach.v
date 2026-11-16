module file

import drm.syncobj
import gpu.agx.gpu
import memory
import usercopy

__global detach_on_copy_file &GpuFile = unsafe { nil }

fn detach_queue_during_copy() {
	detach_on_copy_file.lock.acquire()
	detach_on_copy_file.queues[0] = LogicalQueue{id: 1, detached: true}
	detach_on_copy_file.lock.release()
}

fn check_detached_submission_ownership() {
	for _ in 0 .. 200 {
		gpu.reset()
		mut file := new_file()
		mut manager := gpu.get_global_manager() or { panic('manager') }
		input := output()
		dependency := syncobj.new_fence(1, 1)
		syncobj.replace_fence(input, dependency)
		out := output()
		assert submit(mut file, 1, false, input, out, false) == 0
		assert file.inflight_by_vm[1] == 2
		// The close fixture executes actual QUEUE_DESTROY and its reaper.
		// Here only its namespace result is injected; pending.v and both
		// ioctl submission lookups execute their actual native bodies.
		file.queues[0] = LogicalQueue{id: 1, detached: true}
		attempts := memory.attempts()
		assert submit(mut file, 1, false, unsafe { nil }, output(), false) == -2
		assert memory.attempts() == attempts && pending_count == 1
		service_file_work()
		assert manager.published.len == 0 && file.inflight_by_vm[1] == 2
		syncobj.signal(dependency)
		service_file_work()
		assert manager.published == [u32(12)] && !syncobj.is_signaled(fence(out))
		manager.finish_compute(0)
		assert file.inflight_by_vm[1] == 1, 'aggregate queue owner survives the last callback'
		service_file_work()
		assert syncobj.is_signaled(fence(out))
		assert_drained(file)
		file.queues[0] = LogicalQueue{id: 1}
		detach_on_copy_file = file
		usercopy.before_once(detach_queue_during_copy)
		old := fence(out)
		assert submit(mut file, 1, false, unsafe { nil }, out, false) == -2
		assert voidptr(fence(out)) == voidptr(old)
		assert_drained(file)
		detach_on_copy_file = unsafe { nil }
	}
	println('G13 detached submissions: 200 accepted jobs survive namespace removal and dependencies, refuse new work before staging and after detach during copying, and keep aggregate VM ownership after the last callback until worker retirement')
}
