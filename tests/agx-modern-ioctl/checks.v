module file

import drm
import drm.asahi
import drm.gem
import drm.ioctl
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.params
import gpu.agx.pgtable
import memory
import usercopy

fn check_modern_transport() {
	gpu.available(true)
	gpu.set_running(true)
	driver := drm.DrmDriver{ ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle }
	device := drm.DrmDevice{ driver: unsafe { &driver } }
	// Sizes and directions from the packaged header, independently of the
	// old compatibility structs and the native table's declarations.
	sizes := [u32(24), 16, 24, 8, 24, 24, 16, 40, 40, 8, 40, 16]!
	directions := [u32(1), 3, 3, 1, 1, 3, 3, 3, 3, 1, 1, 3]!
	mut modern_entries := 0
	for entry in driver.ioctls {
		if entry.abi != modern_ioctl_abi { continue }
		assert entry.cmd == 0x40 + u32(modern_entries) && entry.size == sizes[modern_entries]
		assert entry.direction == directions[modern_entries] && entry.extensible
		modern_entries++
	}
	assert modern_entries == 12
	mut modern, mut legacy := GpuFile{}, GpuFile{}
	file_map[0x1111] = unsafe { &modern }
	file_map[0x2222] = unsafe { &legacy }
	mut bytes := [1024]u8{}
	query := asahi.GetParams{ pointer: unsafe { u64(&bytes[8]) }, size: sizeof(asahi.ParamsGlobal) }
	usercopy.configure(unsafe { u64(&bytes[0]) }, sizeof(bytes), -1)
	assert drm.invoke(&device, 0x1111, asahi.get_params, sizeof(query), 1, unsafe { voidptr(&query) }) == 0
	assert modern.ioctl_abi == modern_ioctl_abi && legacy.ioctl_abi == 0
	value := unsafe { &asahi.ParamsGlobal(&bytes[8]) }
	assert value.features == 1 && value.usc_generation == 2 && value.gpu_hal_generation == 0
	assert value.command_timestamp_frequency_hz == 1_000_000_000
	assert value.memory_limit == 0 && value.client_memory_limit == 0
	for index in 0 .. 32 {
		assert value.core_masks[index] == u64(0xa7a7a7a7a7a7a7a7)
	}
	for index in 32 .. 64 {
		assert value.core_masks[index] == 0
	}
	for index in 0 .. 8 {
		assert bytes[index] == 0
	}
	for index in 8 + int(sizeof(asahi.ParamsGlobal)) .. bytes.len {
		assert bytes[index] == 0
	}
	// The same command number means VM_CREATE in legacy and GET_TIME in modern.
	mut time := [4]u64{init: u64(0xabababababababab)}
	time[0] = 0
	usercopy.configure(unsafe { u64(&time[0]) }, sizeof(time), -1)
	assert drm.invoke(&device, 0x1111, asahi.get_time, sizeof(time), 3, unsafe { voidptr(&time[0]) }) == 0
	assert time[1] == 1_000_000_125 && time[2] == u64(0xabababababababab) && time[3] == time[2]
	for size in [u32(0), 1, 8, 16, 24, 64]! {
		mut output := [128]u8{}
		usercopy.configure(unsafe { u64(&output[0]) }, sizeof(output), -1)
		assert drm.invoke(&device, 0x1111, asahi.get_time, size, 2, unsafe { voidptr(&output[0]) }) == 0
	}
	mut old := ioctl.DrmAsahiGetParams{}
	usercopy.configure(unsafe { u64(&old) }, sizeof(old), -1)
	assert drm.invoke(&device, 0x2222, ioctl.drm_asahi_get_params, sizeof(old), 3, unsafe { voidptr(&old) }) == 0
	assert legacy.ioctl_abi == legacy_ioctl_abi
	assert drm.invoke(&device, 0x2222, asahi.get_time, sizeof(asahi.GetTime), 3, unsafe { voidptr(&time[0]) }) == -22
	assert !legacy.select_ioctl_abi(modern_ioctl_abi) && !modern.select_ioctl_abi(legacy_ioctl_abi)
	// Unknown files reach constructor only while the registry lock is held.
	usercopy.configure(unsafe { u64(&time[0]) }, sizeof(time), -1)
	assert drm.invoke(&device, 0x3333, asahi.get_time, sizeof(asahi.GetTime), 3, unsafe { voidptr(&time[0]) }) == -19
	mut vm := asahi.VmCreate{ kernel_start: 0x100000000, kernel_end: 0x120000000 }
	usercopy.configure(unsafe { u64(&vm) }, sizeof(vm), -1)
	assert drm.invoke(&device, 0x1111, asahi.vm_create, sizeof(vm), 3, unsafe { voidptr(&vm) }) == 0 && vm.vm_id == 55
	vm.flags = 1
	assert drm.invoke(&device, 0x1111, asahi.vm_create, sizeof(vm), 3, unsafe { voidptr(&vm) }) == -22
	mut mmap := asahi.GemMmapOffset{ handle: 91 }
	usercopy.configure(unsafe { u64(&mmap) }, sizeof(mmap), -1)
	assert drm.invoke(&device, 0x1111, asahi.gem_mmap_offset, sizeof(mmap), 3, unsafe { voidptr(&mmap) }) == 0
	assert mmap.offset == 0xabc000
	// Advice now reaches the per-file handle lookup; zero is not a handle.
	mut advice := asahi.GemMadvise{}
	usercopy.configure(unsafe { u64(&advice) }, sizeof(advice), -1)
	assert drm.invoke(&device, 0x1111, asahi.gem_madvise, sizeof(advice), 3, unsafe { voidptr(&advice) }) == -2
	file_map.delete(0x1111)
	file_map.delete(0x2222)
	assert modern.close() && legacy.close()
	assert memory.outstanding() == 0
	println('AGX modern transport: production node/table/handlers select per-file ABIs, preserve legacy collisions, extend framing, translate queries and return nanosecond time')
}

fn check_modern_binding() {
	mut cases := 0
	for _ in 0 .. 100 {
		for stride in [u32(sizeof(asahi.GemBindOp)), u32(sizeof(asahi.GemBindOp) + 8)]! {
			mut pt := pgtable.UatPgtable{ watch_start: 0x4000 }
			mut vm := mmu.UatContext{ id: 1, pgtable: unsafe { &pt } }
			mut file := GpuFile{ vms: [unsafe { &vm }] }
			obj := gem.create(7)
			file.objects.table.add_created(obj)
			mut bytes := [128]u8{init: 0xa5}
			first := asahi.GemBindOp{ flags: asahi.bind_read, handle: 7, range: 0x4000, addr: 0x4000 }
			second := asahi.GemBindOp{ flags: asahi.bind_write | asahi.bind_single_page, handle: 7, range: 0x4000, addr: 0x8000 }
			unsafe {
				C.memcpy(&bytes[0], &first, sizeof(first))
				C.memcpy(&bytes[stride], &second, sizeof(second))
			}
			mut request := asahi.VmBind{ vm_id: 1, num_binds: 2, stride: stride, userptr: unsafe { u64(&bytes[0]) } }
			usercopy.fail_read_at(request.userptr + stride)
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == -14 && file.mappings.len == 0 && pt.maps == 0
			usercopy.fail_read_at(0)
			memory.fail_allocations(true)
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == -12 && file.mappings.len == 0
			memory.fail_allocations(false)
			mut bad := second
			bad.handle = 999
			unsafe { C.memcpy(&bytes[stride], &bad, sizeof(bad)) }
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == -2 && file.mappings.len == 1
			assert pt.leaves[0] == obj.phys_addr && pt.leaves[1] == 0
			unsafe { C.memcpy(&bytes[stride], &second, sizeof(second)) }
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == 0 && file.mappings.len == 2
			assert pt.protections[0] == pgtable.gpu_prot_gpu_shared_ro && pt.protections[1] == pgtable.gpu_prot_gpu_shared_wo
			assert pt.leaves[1] == obj.phys_addr && obj.references == 3
			mut unbind := asahi.GemBindOp{ flags: asahi.bind_unbind, range: 0x8000, addr: 0x4000 }
			request.num_binds = 1
			request.stride = sizeof(unbind)
			request.userptr = unsafe { u64(&unbind) }
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == 0 && file.mappings.len == 0 && obj.references == 1
			// A short operation retains its low address bytes, with omitted high bytes zero.
			request.userptr = unsafe { u64(&first) }
			request.stride = sizeof(first) - 1
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == 0 && file.mappings.len == 1
			assert file.close() && vm.destroyed && gem.live() == 0
			memory.assert_released()
			cases += 6
		}
	}
	mut file := GpuFile{}
	assert file.ioctl_modern_vm_bind(&asahi.VmBind{ stride: 1 }) == 0
	assert file.ioctl_modern_vm_bind(&asahi.VmBind{}) == -22
	assert file.ioctl_modern_vm_bind(&asahi.VmBind{ stride: 32, num_binds: 1, userptr: ~u64(0) - 4 }) == -14
	assert cases == 1200
	println('AGX modern VM_BIND: 1200 real mapping checks cover immutable batch copy, copy/OOM refusal before mutation, prefix errors, strided/short records and read/write/single-page translation')
}

pub fn run_modern_checks() {
	mut manager := mmu.UatManager{}
	uat_mgr = unsafe { &manager }
	defer { uat_mgr = unsafe { nil } }
	check_modern_transport()
	check_modern_binding()
	check_modern_queue_and_object()
	run_advice_checks()
	run_modern_scs_checks()
	assert params.timestamp_ns(24_000_003, 24_000_000) == 1_000_000_125
	assert params.timestamp_ns(1_000_003, 1_000_000) == 1_000_003_000
}

fn check_modern_queue_and_object() {
	gpu.available(true)
	gpu.set_running(true)
	mut pt := pgtable.UatPgtable{}
	mut vm := mmu.UatContext{ id: 1, pgtable: unsafe { &pt } }
	mut file := GpuFile{ vms: [unsafe { &vm }] }
	driver := drm.DrmDriver{ ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle }
	device := drm.DrmDevice{ driver: unsafe { &driver } }
	file_map[0x4444] = unsafe { &file }
	mut queue := asahi.QueueCreate{ vm_id: 1, priority: 1, usc_exec_base: 0x120000000 }
	usercopy.configure(unsafe { u64(&queue) }, sizeof(queue), -1)
	assert drm.invoke(&device, 0x4444, asahi.queue_create, sizeof(queue), 3, unsafe { voidptr(&queue) }) == 0
	assert queue.queue_id != 0 && file.queues.len == 1
	assert file.queues[0].usc_base == queue.usc_exec_base && file.queues[0].caps == 5
	captured := file.capture_submission_queue(queue.queue_id) or { panic('modern capture') }
	assert captured.usc_base == queue.usc_exec_base && captured.resources.has_file_references()
	destroy := asahi.QueueDestroy{ queue_id: queue.queue_id, pad: 0xffffffff }
	assert drm.invoke(&device, 0x4444, asahi.queue_destroy, sizeof(destroy), 1, unsafe { voidptr(&destroy) }) == 0
	assert file.capture_submission_queue(queue.queue_id) == none
	assert !captured.resources.released, 'captured modern queue must survive name deletion'
	release_submission_queue(captured)
	file.lock.acquire()
	file.reap_detached_g13_queues_locked()
	file.lock.release()
	assert file.queues.len == 0 && file.g13_queues.len == 0
	mut object := asahi.GemCreate{ size: 0x4001, pad: 0xffffffff }
	usercopy.configure(unsafe { u64(&object) }, sizeof(object), -1)
	assert drm.invoke(&device, 0x4444, asahi.gem_create, sizeof(object), 3, unsafe { voidptr(&object) }) == 0
	assert object.handle != 0 && object.size == 0x4001
	owned := file.objects.get_ref(object.handle) or { panic('modern GEM handle') }
	assert owned.size == 0x8000
	gem.unref(owned)
	file_map.delete(0x4444)
	assert file.close() && vm.destroyed && gem.live() == 0
	memory.assert_released()
	println('AGX modern queue/GEM ioctls: registered creation stores USC before publication, retained captures survive name removal, final ownership drains and rounded objects keep wire output semantics')
}
