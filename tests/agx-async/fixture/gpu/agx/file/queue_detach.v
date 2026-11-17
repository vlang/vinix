module file

import drm.syncobj
import gpu.agx.gpu
import memory
import usercopy

__global detach_on_copy_file &GpuFile = unsafe { nil }

fn detach_queue_during_copy() {
	detach_on_copy_file.lock.acquire()
	assert detach_on_copy_file.vm.inflight == 0, 'capture must preserve idle mapping cleanup and bind admission'
	assert detach_on_copy_file.g13_queues[0].resources.has_file_references()
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
		assert file.vm.inflight == 2
		assert file.g13_queues[0].resources.has_file_references()
		// The close fixture executes actual QUEUE_DESTROY and its reaper.
		// Here only its namespace result is injected; pending.v and both
		// ioctl queue capture executes its actual native body.
		file.queues[0] = LogicalQueue{id: 1, detached: true}
		attempts := memory.attempts()
		assert submit(mut file, 1, false, unsafe { nil }, output(), false) == -2
		assert memory.attempts() == attempts && pending_count == 1
		service_file_work()
		assert manager.published.len == 0 && file.vm.inflight == 2
		syncobj.signal(dependency)
		service_file_work()
		assert manager.published == [u32(12)] && !syncobj.is_signaled(fence(out))
		manager.finish_compute(0)
		assert file.vm.inflight == 1, 'aggregate queue owner survives the last callback'
		service_file_work()
		assert syncobj.is_signaled(fence(out))
		assert_drained(file)
		file.queues[0] = LogicalQueue{id: 1}
		detach_on_copy_file = file
		usercopy.before_once(detach_queue_during_copy)
		old := fence(out)
		assert submit(mut file, 1, false, unsafe { nil }, out, false) == 0
		assert voidptr(fence(out)) != voidptr(old)
		assert file.g13_queues[0].resources.has_file_references()
		service_file_work()
		manager.finish_compute(0)
		service_file_work()
		assert_drained(file)
		detach_on_copy_file = unsafe { nil }
	}
	println('G13 detached submissions: 200 accepted jobs and 200 captures survive namespace removal/dependencies and detach during copying; new names reject before staging; queue and aggregate VM ownership survive callbacks until worker retirement')
}
