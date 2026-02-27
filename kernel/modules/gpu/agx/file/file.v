@[has_globals]
module file

// Per-fd state and ioctl handlers for the Asahi GPU DRM driver
// Each open file descriptor gets a GpuFile that owns a VM context
// and a set of work queues. Implements all custom Asahi ioctls
// (GET_PARAMS through SUBMIT) for Phase 10 integration.

import drm
import drm.ioctl
import drm.gem
import drm.syncobj
import gpu.agx.mmu
import gpu.agx.workqueue
import gpu.agx.event
import gpu.agx.queue
import gpu.agx.gpu
import klock

pub struct GpuFile {
pub mut:
	dev    &drm.DrmDevice             = unsafe { nil }
	vm     &mmu.UatContext            = unsafe { nil }
	queues []&workqueue.WorkQueue
	lock   klock.Lock
}

__global (
	file_map_lock klock.Lock
	file_map = map[u64]&GpuFile{}
)

fn get_or_create_file(handle voidptr, dev &drm.DrmDevice) ?&GpuFile {
	if handle == unsafe { nil } {
		return none
	}

	key := u64(handle)

	file_map_lock.acquire()
	if key in file_map {
		f := file_map[key] or {
			file_map_lock.release()
			return none
		}
		file_map_lock.release()
		return f
	}
	file_map_lock.release()

	f := new_gpu_file(dev) or { return none }

	file_map_lock.acquire()
	file_map[key] = f
	file_map_lock.release()
	return f
}

pub fn release_handle(_dev &drm.DrmDevice, handle voidptr) {
	if handle == unsafe { nil } {
		return
	}
	key := u64(handle)

	file_map_lock.acquire()
	f := file_map[key] or {
		file_map_lock.release()
		return
	}
	file_map.delete(key)
	file_map_lock.release()

	mut ff := unsafe { f }
	ff.close()
}

// Create a new GPU file associated with a DRM device.
// Allocates a fresh VM context for this file's GPU address space.
pub fn new_gpu_file(dev &drm.DrmDevice) ?&GpuFile {
	if dev == unsafe { nil } {
		return none
	}

	// Allocate a VM context from the UAT manager
	mgr := uat_mgr
	if mgr == unsafe { nil } {
		C.printf(c'agx file: UAT manager not initialized\n')
		return none
	}

	mut m := unsafe { mgr }
	vm := m.create_context() or {
		C.printf(c'agx file: failed to allocate VM context\n')
		return none
	}
	m.bind_context(vm)

	return &GpuFile{
		dev: unsafe { dev }
		vm:  vm
	}
}

// Close the GPU file: destroy all queues and release the VM context.
pub fn (mut f GpuFile) close() {
	f.lock.acquire()
	defer {
		f.lock.release()
	}

	// Destroy all work queues
	for mut q in f.queues {
		q.destroy()
	}
	f.queues.clear()

	// Destroy the VM context
	if f.vm != unsafe { nil } {
		mgr := uat_mgr
		if mgr != unsafe { nil } {
			mut m := unsafe { mgr }
			m.destroy_context(f.vm)
		}
		f.vm = unsafe { nil }
	}
}

// GET_PARAMS ioctl handler -- return GPU hardware parameters.
pub fn (f &GpuFile) ioctl_get_params(data &ioctl.DrmAsahiGetParams) int {
	mut params := unsafe { data }
	match params.param {
		0 { // GPU_UNSTABLE_UABI_VERSION
			params.value = 1
		}
		1 { // GPU_CHIP_ID
			params.value = 0x8103 // M1
		}
		2 { // GPU_NUM_CORES
			params.value = 8
		}
		3 { // GPU_NUM_CLUSTERS
			params.value = 1
		}
		else {
			return -22 // EINVAL
		}
	}
	return 0
}

// VM_CREATE ioctl handler -- create a new GPU VM context.
pub fn (f &GpuFile) ioctl_vm_create(data &ioctl.DrmAsahiVmCreate) int {
	mut vm := unsafe { data }

	mgr := uat_mgr
	if mgr == unsafe { nil } {
		return -19 // ENODEV
	}

	mut m := unsafe { mgr }
	ctx := m.create_context() or {
		return -12 // ENOMEM
	}
	m.bind_context(ctx)

	vm.vm_id = ctx.id
	return 0
}

// VM_DESTROY ioctl handler -- destroy a GPU VM context.
pub fn (f &GpuFile) ioctl_vm_destroy(data &ioctl.DrmAsahiVmDestroy) int {
	vm := unsafe { data }

	mgr := uat_mgr
	if mgr == unsafe { nil } {
		return -19 // ENODEV
	}

	// Look up and destroy the context by ID
	// The UAT manager validates the ID range
	mut m := unsafe { mgr }
	if vm.vm_id >= mmu.uat_num_contexts {
		return -22 // EINVAL
	}
	ctx := m.contexts[vm.vm_id]
	if ctx == unsafe { nil } {
		return -22 // EINVAL
	}

	m.destroy_context(ctx)
	return 0
}

// GEM_CREATE ioctl handler -- allocate a GEM buffer object.
pub fn (f &GpuFile) ioctl_gem_create(data &ioctl.DrmAsahiGemCreate) int {
	mut gc := unsafe { data }

	obj := gem.create(gc.size) or {
		return -12 // ENOMEM
	}

	gc.handle = obj.handle
	return 0
}

// GEM_MMAP_OFFSET ioctl handler -- get mmap offset for a GEM object.
pub fn (f &GpuFile) ioctl_gem_mmap_offset(data &ioctl.DrmAsahiGemMmapOffset) int {
	mut mmo := unsafe { data }

	obj := gem.get_by_handle(mmo.handle) or {
		return -2 // ENOENT
	}

	mmo.offset = gem.create_mmap_offset(obj)
	return 0
}

// GEM_BIND ioctl handler -- bind a GEM object into a VM address space.
pub fn (f &GpuFile) ioctl_gem_bind(data &ioctl.DrmAsahiGemBind) int {
	bind := unsafe { data }

	obj := gem.get_by_handle(bind.handle) or {
		return -2 // ENOENT
	}

	mgr := uat_mgr
	if mgr == unsafe { nil } {
		return -19 // ENODEV
	}

	// Look up the target VM context
	if bind.vm_id >= mmu.uat_num_contexts {
		return -22 // EINVAL
	}
	ctx := mgr.contexts[bind.vm_id]
	if ctx == unsafe { nil } {
		return -22 // EINVAL
	}

	if ctx.pgtable == unsafe { nil } {
		return -22 // EINVAL
	}

	// Map the GEM object's physical pages into the VM at the requested address
	mut pt := unsafe { ctx.pgtable }
	if !pt.map(bind.addr, obj.phys_addr + bind.offset, bind.range, 0x43) {
		return -12 // ENOMEM
	}
	mut m := unsafe { mgr }
	m.flush(ctx)

	return 0
}

// QUEUE_CREATE ioctl handler -- create a GPU work queue.
pub fn (mut f GpuFile) ioctl_queue_create(data &ioctl.DrmAsahiQueueCreate) int {
	mut qc := unsafe { data }

	vm_id := if f.vm != unsafe { nil } { f.vm.vm_id } else { qc.vm_id }

	wq := workqueue.new_workqueue(u32(f.queues.len), vm_id, qc.priority) or {
		return -12 // ENOMEM
	}

	f.lock.acquire()
	f.queues << wq
	qc.queue_id = wq.id
	f.lock.release()

	return 0
}

// QUEUE_DESTROY ioctl handler -- destroy a GPU work queue.
pub fn (mut f GpuFile) ioctl_queue_destroy(data &ioctl.DrmAsahiQueueDestroy) int {
	qd := unsafe { data }

	f.lock.acquire()
	defer {
		f.lock.release()
	}

	for i, mut q in f.queues {
		if q.id == qd.queue_id {
			q.destroy()
			f.queues.delete(i)
			return 0
		}
	}

	return -22 // EINVAL
}

// SUBMIT ioctl handler -- submit GPU work to a queue.
pub fn (mut f GpuFile) ioctl_submit(data &ioctl.DrmAsahiSubmit) int {
	submit := unsafe { data }

	// Find the target queue
	mut target_q := unsafe { &workqueue.WorkQueue(nil) }
	for q in f.queues {
		if q.id == submit.queue_id {
			target_q = unsafe { q }
			break
		}
	}

	if target_q == unsafe { nil } {
		return -22 // EINVAL
	}

	// Validate command count
	if submit.cmd_count == 0 || submit.cmds == 0 {
		return -22 // EINVAL
	}

	// Wait on all in_sync fences before proceeding
	if submit.in_sync_count > 0 && submit.in_syncs != 0 {
		for i := u32(0); i < submit.in_sync_count; i++ {
			sync_item := unsafe { &ioctl.DrmAsahiSyncItem(submit.in_syncs + u64(i) * sizeof(ioctl.DrmAsahiSyncItem)) }
			obj := syncobj.lookup(sync_item.handle) or { continue }
			if obj.fence != unsafe { nil } {
				syncobj.wait(obj.fence, 5_000_000_000)
			}
		}
	}

	// Create an out_sync fence for this submission
	fence := syncobj.new_fence(0, 0)

	// Allocate a stamp slot from the event manager for GPU completion tracking
	stamp_idx := gpu_event_mgr.alloc_stamp() or {
		return -12 // ENOMEM
	}
	stamp_value := gpu_event_mgr.next_stamp_value()
	stamp_addr := gpu_event_mgr.get_stamp_addr(stamp_idx)
	gpu_event_mgr.set_fence(stamp_idx, fence)
	gpu_event_mgr.set_expected(stamp_idx, stamp_value)

	// Process each command in the array
	cmd_ptr := submit.cmds
	mut tq := unsafe { target_q }
	mut mgr := gpu.get_global_manager() or {
		gpu_event_mgr.free_stamp(stamp_idx)
		return -19 // ENODEV
	}
	for ci := u32(0); ci < submit.cmd_count; ci++ {
		cmd := unsafe { &ioctl.DrmAsahiCmd(cmd_ptr + u64(ci) * sizeof(ioctl.DrmAsahiCmd)) }

		match cmd.cmd_type {
			ioctl.asahi_cmd_render {
				// Build render command from user parameters
				render_cmd := queue.RenderCommand{
					cmd_type:       0
					flags:          cmd.flags
					vertex_buf_addr: cmd.vertex_buf
					vertex_buf_size: cmd.vertex_size
					vertex_count:   cmd.vertex_count
					instance_count: cmd.instance_count
					frag_buf_addr:  cmd.frag_buf
					frag_buf_size:  cmd.frag_size
					tile_width:     cmd.tile_width
					tile_height:    cmd.tile_height
					scene_addr:     cmd.scene_addr
					tvb_addr:       cmd.tvb_addr
					width:          cmd.width
					height:         cmd.height
					layers:         if cmd.layers > 0 { cmd.layers } else { u32(1) }
					samples:        if cmd.samples > 0 { cmd.samples } else { u32(1) }
					stamp_addr:     stamp_addr
					stamp_value:    stamp_value
					result_addr:    cmd.result_buf
					result_size:    cmd.result_size
				}

				if !queue.validate_render_cmd(&render_cmd) {
					gpu_event_mgr.free_stamp(stamp_idx)
					return -22 // EINVAL
				}

				// Create work item and submit to queue
				mut item := &workqueue.WorkItem{
					cmd_type:    0
					stamp_value: stamp_value
					fence:       fence
					timeout_ns:  5_000_000_000
				}

				slot := tq.submit(item) or {
					gpu_event_mgr.free_stamp(stamp_idx)
					return -16 // EBUSY
				}
				item.slot = slot

				if !mgr.submit_render(&render_cmd, tq.priority) {
					tq.complete(slot, workqueue.work_err_channel_error)
					gpu_event_mgr.free_stamp(stamp_idx)
					return -5 // EIO
				}
			}
			ioctl.asahi_cmd_compute {
				// Build compute command from user parameters
				compute_cmd := queue.ComputeCommand{
					flags:            cmd.flags
					compute_buf_addr: cmd.compute_buf
					compute_buf_size: cmd.compute_size
					wg_x:             cmd.wg_x
					wg_y:             cmd.wg_y
					wg_z:             cmd.wg_z
					grid_x:           cmd.grid_x
					grid_y:           cmd.grid_y
					grid_z:           cmd.grid_z
					shared_mem_size:  cmd.shared_mem
					stamp_addr:       stamp_addr
					stamp_value:      stamp_value
					result_addr:      cmd.result_buf
					result_size:      cmd.result_size
				}

				if !queue.validate_compute_cmd(&compute_cmd) {
					gpu_event_mgr.free_stamp(stamp_idx)
					return -22 // EINVAL
				}

				mut item := &workqueue.WorkItem{
					cmd_type:    2
					stamp_value: stamp_value
					fence:       fence
					timeout_ns:  5_000_000_000
				}

				slot := tq.submit(item) or {
					gpu_event_mgr.free_stamp(stamp_idx)
					return -16 // EBUSY
				}
				item.slot = slot

				if !mgr.submit_compute(&compute_cmd, tq.priority) {
					tq.complete(slot, workqueue.work_err_channel_error)
					gpu_event_mgr.free_stamp(stamp_idx)
					return -5 // EIO
				}
			}
			else {
				gpu_event_mgr.free_stamp(stamp_idx)
				return -22 // EINVAL: unknown command type
			}
		}
	}

	// Bind out_sync fence to any requested sync objects
	if submit.out_sync_count > 0 && submit.out_syncs != 0 {
		for i := u32(0); i < submit.out_sync_count; i++ {
			sync_item := unsafe { &ioctl.DrmAsahiSyncItem(submit.out_syncs + u64(i) * sizeof(ioctl.DrmAsahiSyncItem)) }
			obj := syncobj.lookup(sync_item.handle) or { continue }
			syncobj.replace_fence(obj, fence)
		}
	}

	return 0
}

fn dispatch(handle voidptr, dev &drm.DrmDevice) ?&GpuFile {
	return get_or_create_file(handle, dev)
}

fn ioctl_get_params_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	return f.ioctl_get_params(unsafe { &ioctl.DrmAsahiGetParams(data) })
}

fn ioctl_vm_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	return f.ioctl_vm_create(unsafe { &ioctl.DrmAsahiVmCreate(data) })
}

fn ioctl_vm_destroy_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	return f.ioctl_vm_destroy(unsafe { &ioctl.DrmAsahiVmDestroy(data) })
}

fn ioctl_gem_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	return f.ioctl_gem_create(unsafe { &ioctl.DrmAsahiGemCreate(data) })
}

fn ioctl_gem_mmap_offset_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	return f.ioctl_gem_mmap_offset(unsafe { &ioctl.DrmAsahiGemMmapOffset(data) })
}

fn ioctl_gem_bind_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	return f.ioctl_gem_bind(unsafe { &ioctl.DrmAsahiGemBind(data) })
}

fn ioctl_queue_create_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut ff := unsafe { f }
	return ff.ioctl_queue_create(unsafe { &ioctl.DrmAsahiQueueCreate(data) })
}

fn ioctl_queue_destroy_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut ff := unsafe { f }
	return ff.ioctl_queue_destroy(unsafe { &ioctl.DrmAsahiQueueDestroy(data) })
}

fn ioctl_submit_handler(dev &drm.DrmDevice, handle voidptr, data voidptr) int {
	f := dispatch(handle, dev) or { return -19 }
	mut ff := unsafe { f }
	return ff.ioctl_submit(unsafe { &ioctl.DrmAsahiSubmit(data) })
}

pub fn drm_ioctls() []drm.DrmIoctl {
	return [
		drm.DrmIoctl{cmd: ioctl.drm_asahi_get_params, handler: ioctl_get_params_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_vm_create, handler: ioctl_vm_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_vm_destroy, handler: ioctl_vm_destroy_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_create, handler: ioctl_gem_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_mmap_offset, handler: ioctl_gem_mmap_offset_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_gem_bind, handler: ioctl_gem_bind_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_queue_create, handler: ioctl_queue_create_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_queue_destroy, handler: ioctl_queue_destroy_handler},
		drm.DrmIoctl{cmd: ioctl.drm_asahi_submit, handler: ioctl_submit_handler},
	]
}
