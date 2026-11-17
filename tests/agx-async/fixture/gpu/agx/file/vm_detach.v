// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.syncobj
import gpu.agx.gpu
import usercopy

__global vm_detach_copy_file &GpuFile = unsafe { nil }

fn detach_vm_during_copy() {
	// The close fixture executes actual VM_DESTROY. Inject its namespace
	// result here while the actual submit body owns its captured queue.
	vm_detach_copy_file.lock.acquire()
	assert vm_detach_copy_file.vm.inflight == 0
	assert vm_detach_copy_file.g13_queues[0].resources.has_file_references()
	vm_detach_copy_file.vm.detached = true
	vm_detach_copy_file.lock.release()
}

fn check_detached_vm_submissions() {
	for _ in 0 .. 200 {
		gpu.reset()
		mut file := new_file()
		file.vm.id = 65
		file.queues[0] = LogicalQueue{id: 1, vm_id: 65}
		file.queues[1] = LogicalQueue{id: 2, vm_id: 65}
		mut manager := gpu.get_global_manager() or { panic('manager') }
		out := output()
		vm_detach_copy_file = file
		usercopy.before_once(detach_vm_during_copy)
		assert submit(mut file, 1, false, unsafe { nil }, out, false) == 0
		if _ := file.find_vm(1) { panic('detached name visible') }
		service_file_work()
		manager.finish_compute(0)
		service_file_work()
		assert syncobj.is_signaled(fence(out))
		assert_drained(file)
		// Other existing queues retain the same physical VM after its name
		// disappears; subsequent submissions must not repeat user lookup.
		assert submit(mut file, 2, false, unsafe { nil }, out, false) == 0
		service_file_work()
		manager.finish_compute(0)
		service_file_work()
		assert_drained(file)
		vm_detach_copy_file = unsafe { nil }
	}
	println('G13 detached VM submissions: 200 removals during copying and 200 later submissions through existing queues complete with balanced queue/VM owners')
}
