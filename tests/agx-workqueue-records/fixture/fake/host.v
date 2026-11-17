module fake

import drm.gem
import drm.ioctl
import gpu.agx.workqueue
import klock

#include <sanitizer/asan_interface.h>
fn C.__asan_address_is_poisoned(voidptr) int

struct FakeG17Vm {
mut:
	jobs u32
	destroyed bool
}
fn (mut vm FakeG17Vm) finish_job() { assert vm.jobs > 0; vm.jobs-- }
fn (mut vm FakeG17Vm) destroy() { assert vm.jobs == 0 && !vm.destroyed; vm.destroyed = true }
struct Objects {}
fn (mut objects Objects) release_all() {}
struct FakeG17File {
mut:
	queues []&workqueue.WorkQueue
	vms []&FakeG17Vm
	closed_objects []&gem.GemObject
	objects Objects
	inflight_jobs u32
	closing bool
	closed bool
	lock klock.Lock
}
fn (mut file FakeG17File) cleanup_closed_objects_locked() { assert file.lock.is_held() }

pub fn check_fake_owners() {
	for count in [1, 3, 127]! {
		for pending in 0 .. 4 {
			mut file := FakeG17File{}
			file.queues.flags |= .noslices
			mut saved := []&workqueue.WorkQueue{}; saved.flags |= .noslices
			mut items := [127]workqueue.WorkItem{}
			for i in 0 .. count {
				mut queue := workqueue.new_workqueue(u32(i + 1), 1, 0, 1) or { panic('queue') }
				if pending != 0 { assert (queue.submit(unsafe { &items[i] }) or { panic('slot') }) == 0 }
				file.queues << queue; saved << queue
			}
			if pending != 0 {
				file.inflight_jobs = u32(count)
				file.close()
				assert !file.closed && file.queues.len == count
				for i, mut queue in saved {
					assert C.__asan_address_is_poisoned(queue) == 0
					request := ioctl.DrmAsahiQueueDestroy{queue_id: u32(i + 1)}
					assert file.ioctl_queue_destroy(&request) == -16
					queue.complete(0, 0)
					// Idle destruction can run after the worker's last queue access,
					// before finish_pending_job drops the separate file/VM pin.
					if pending == 2 { assert file.ioctl_queue_destroy(&request) == 0 }
					mut vm := FakeG17Vm{jobs: 1}
					file.finish_pending_job(mut vm)
					assert vm.jobs == 0
					if i + 1 < count { assert !file.closed }
				}
			} else { file.close() }
			assert file.closed && file.queues.len == 0
			for queue in saved { assert C.__asan_address_is_poisoned(queue) != 0, 'fake final queue owners must free metadata' }
			file.close()
			unsafe { file.queues.free(); saved.free() }
		}
	}
	// Delete first/middle/last rows with other live records still installed.
	for target in 0 .. 3 {
		mut file := FakeG17File{}
		mut saved := unsafe { [3]&workqueue.WorkQueue{} }
		for i in 0 .. 3 {
			queue := workqueue.new_workqueue(u32(i + 1), 1, 0, 1) or { panic('queue') }
			saved[i] = queue; file.queues << queue
		}
		assert file.ioctl_queue_destroy(&ioctl.DrmAsahiQueueDestroy{queue_id: u32(target + 1)}) == 0
		for i in 0 .. 3 { assert (C.__asan_address_is_poisoned(saved[i]) != 0) == (i == target), 'destroy must free the original pointer before array deletion shifts its alias' }
		file.close(); unsafe { file.queues.free() }
	}
	for id in 1 .. 129 {
		queue := workqueue.new_workqueue(u32(id), 1, 0, 1) or { panic('queue') }
		mut file := FakeG17File{queues: [queue]}
		assert file.ioctl_queue_destroy(&ioctl.DrmAsahiQueueDestroy{queue_id: u32(id), pad: 1}) == -22
		assert C.__asan_address_is_poisoned(queue) == 0
		assert file.ioctl_queue_destroy(&ioctl.DrmAsahiQueueDestroy{queue_id: u32(id)}) == 0
		assert file.queues.len == 0 && C.__asan_address_is_poisoned(queue) != 0, 'idle fake queue destroy must free metadata'
		assert file.ioctl_queue_destroy(&ioctl.DrmAsahiQueueDestroy{queue_id: u32(id)}) == -22
		unsafe { file.queues.free() }
	}
	println('AGX logical queues: 143 fake close/destroy cases, pending workers, final pin and shifted owner arrays passed')
}

fn measure_cycle(mut file FakeG17File) {
	queue := workqueue.new_workqueue(1, 1, 0, 1) or { panic('queue') }
	file.closed = false; file.closing = false; file.queues << queue
	file.close()
	assert file.closed && file.queues.len == 0
}
pub fn measure() {
	mut file := FakeG17File{}
	file.queues.flags |= .noslices
	for _ in 0 .. 1000 { measure_cycle(mut file) }
	live_record_heap()
	for round in 0 .. 3 {
		a, b := live_record_heap()
		for _ in 0 .. 10000 { measure_cycle(mut file) }
		c, d := live_record_heap()
		C.printf(c'AGX-WORKQUEUE-RECORDS round=%d closes=10000 retained_blocks=%lld retained_bytes=%lld sizeof_queue=%u\n', round, i64(c) - i64(a), i64(d) - i64(b), u32(sizeof(workqueue.WorkQueue)))
		assert c == a && d == b, 'logical queue close must not retain metadata'
	}
	unsafe { file.queues.free() }
}
