module file

import drm
import drm.asahi
import drm.gem
import drm.ioctl
import gpu.agx.bo
import gpu.agx.gpu
import gpu.agx.mmu
import gpu.agx.params
import gpu.agx.pgtable
import gpu.agx.workqueue
import memory
import os
import proc
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
	mut wire := []u64{}
	mut modern_entries := 0
	for entry in driver.ioctls {
		if entry.abi != modern_ioctl_abi { continue }
		assert modern_entries < sizes.len
		assert entry.cmd == 0x40 + u32(modern_entries) && entry.size == sizes[modern_entries]
		assert entry.direction == directions[modern_entries] && entry.extensible
		wire << drm.request(entry.cmd, entry.size, entry.direction)
		modern_entries++
	}
	assert modern_entries == 12
	if path := os.getenv_opt('AGX_ASAHI_WIRE_ORACLE') {
		reference := (os.read_lines(path) or { panic(err) }).filter(it.starts_with('Asahi ioctl encodings: '))
		assert reference == ['Asahi ioctl encodings: ${wire}'], 'registered ioctl words differ from the pinned C header'
		println('AGX modern transport: all 12 registered ioctl words match the pinned C header')
	}
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
	mut context := mmu.UatContext{ id: 55 }
	mut manager := unsafe { uat_mgr }
	manager.next_context = unsafe { &context }
	mut vm := asahi.VmCreate{ kernel_start: 0x100000000, kernel_end: 0x120000000 }
	usercopy.configure(unsafe { u64(&vm) }, sizeof(vm), -1)
	assert drm.invoke(&device, 0x1111, asahi.vm_create, sizeof(vm), 3, unsafe { voidptr(&vm) }) == 0 && vm.vm_id == 1
	assert context.vm_id == 1 && context.id == 1
	vm.flags = 1
	assert drm.invoke(&device, 0x1111, asahi.vm_create, sizeof(vm), 3, unsafe { voidptr(&vm) }) == -22
	mapped := gem.create(91)
	modern.objects.add_created(mapped)
	mut mmap := asahi.GemMmapOffset{ handle: 91 }
	usercopy.configure(unsafe { u64(&mmap) }, sizeof(mmap), -1)
	assert drm.invoke(&device, 0x1111, asahi.gem_mmap_offset, sizeof(mmap), 3, unsafe { voidptr(&mmap) }) == 0
	assert mmap.offset == gem.create_mmap_offset(mapped)
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
	driver := drm.DrmDriver{ ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle }
	device := drm.DrmDevice{ driver: unsafe { &driver } }
	mut cases := 0
	for _ in 0 .. 100 {
		for stride in [u32(sizeof(asahi.GemBindOp)), u32(sizeof(asahi.GemBindOp) + 8)]! {
			mut pt := pgtable.UatPgtable{ watch_start: 0x4000 }
			mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
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
			mut unbind := asahi.GemBindOp{ flags: asahi.bind_unbind, range: 0x4000, addr: 0x4000 }
			third := asahi.GemBindOp{ flags: asahi.bind_read, handle: 7, range: 0x4000, addr: 0xc000 }
			before_unmaps := pt.unmaps
			file_map[0x4444] = unsafe { &file }
			// A job holding the VM does not hold its bindings, as on Asahi's G13
			// path: a hole, a live unbind and a replacing map all proceed.
			vm.inflight = 1
			unbind.addr = 0x10000
			unsafe {
				C.memcpy(&bytes[0], &unbind, sizeof(unbind))
				C.memcpy(&bytes[stride], &third, sizeof(third))
			}
			assert drm.invoke(&device, 0x4444, asahi.vm_bind, sizeof(request), 1, unsafe { voidptr(&request) }) == 0
			assert file.mappings.len == 3 && pt.leaves[2] == obj.phys_addr && pt.unmaps == before_unmaps && obj.references == 4
			unbind.addr = 0x4000
			unsafe {
				C.memcpy(&bytes[0], &unbind, sizeof(unbind))
				C.memcpy(&bytes[stride], &first, sizeof(first))
			}
			assert drm.invoke(&device, 0x4444, asahi.vm_bind, sizeof(request), 1, unsafe { voidptr(&request) }) == 0
			assert file.mappings.len == 3 && pt.leaves[0] == obj.phys_addr && pt.unmaps == before_unmaps + 1
			assert obj.references == 4
			unbind.addr = 0x10000
			unsafe { C.memcpy(&bytes[0], &unbind, sizeof(unbind)) }
			assert drm.invoke(&device, 0x4444, asahi.vm_bind, sizeof(request), 1, unsafe { voidptr(&request) }) == 0
			assert file.mappings.len == 3 && pt.leaves[0] == obj.phys_addr && pt.unmaps == before_unmaps + 2
			assert pt.protections[0] == pgtable.gpu_prot_gpu_shared_ro && obj.references == 4
			vm.inflight = 0
			file_map.delete(0x4444)
			unbind.addr = 0x4000
			unbind.range = 0xc000
			request.num_binds = 1
			request.stride = sizeof(unbind)
			request.userptr = unsafe { u64(&unbind) }
			gpu.fail_mapping_check_after(1)
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == -5
			assert file.mappings.len == 2 && file.mappings[0].retiring && obj.references == 3
			assert pt.leaves[0] == 0 && pt.leaves[1] == 0 && pt.leaves[2] == obj.phys_addr
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == 0 && file.mappings.len == 0 && obj.references == 1
			// A short operation retains its low address bytes, with omitted high bytes zero.
			request.userptr = unsafe { u64(&first) }
			request.stride = sizeof(first) - 1
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == 0 && file.mappings.len == 1
			assert file.close() && vm.destroyed && gem.live() == 0
			memory.assert_released()
			cases += 9
		}
	}
	mut file := GpuFile{}
	assert file.ioctl_modern_vm_bind(&asahi.VmBind{ stride: 1 }) == 0
	assert file.ioctl_modern_vm_bind(&asahi.VmBind{}) == -22
	assert cases == 1800
	println('AGX modern VM_BIND: ${cases} real mapping checks cover immutable batch copy, copy/OOM refusal before mutation, prefix errors, failed retirement suffix preservation, busy-VM unbind, strided/short records and read/write/single-page translation')
}

fn check_modern_bind_staging_order() {
	mut file := GpuFile{}
	mut manager := gpu.get_global_manager() or { panic('missing test manager') }
	assert manager.hw_config.gpu_gen == .g13
	for pointer in [u64(0), ~u64(0) - 4]! {
		mut request := asahi.VmBind{ stride: 32, num_binds: 1, userptr: pointer }
		for oom in [true, false]! {
			memory.fail_allocations(oom)
			usercopy.fail_read_at(0)
			calls := memory.calls()
			assert file.ioctl_modern_vm_bind(unsafe { &request }) == if oom { -12 } else { -14 }
			assert memory.calls() == calls + 1
			assert usercopy.reads() == if oom { 0 } else { 1 }
			assert file.mappings.len == 0 && memory.outstanding() == 0
		}
		usercopy.fail_read_at(0)
		calls := memory.calls()
		// The widened product fits usize but exceeds Asahi's KVec capacity.
		request.stride = 0x80000001
		request.num_binds = 0xffffffff
		assert file.ioctl_modern_vm_bind(unsafe { &request }) == -12
		request.num_binds = 0
		assert file.ioctl_modern_vm_bind(unsafe { &request }) == 0
		request.pad = 1
		assert file.ioctl_modern_vm_bind(unsafe { &request }) == -22
		assert memory.calls() == calls && usercopy.reads() == 0 && file.mappings.len == 0
		request.pad = 0
		request.num_binds = 1
		request.stride = 32
		memory.fail_allocations(true)
		manager.hw_config.gpu_gen = .g17
		assert file.ioctl_modern_vm_bind(unsafe { &request }) == -14
		manager.hw_config.gpu_gen = .g13
		file.registration_manager = unsafe { nil }
		assert file.ioctl_modern_vm_bind(unsafe { &request }) == -14
		file.registration_manager = manager
		memory.fail_allocations(false)
		assert memory.calls() == calls && usercopy.reads() == 0
	}
	println('AGX modern VM_BIND staging: 14 G13 and shared-handler cases preserve error order without mapping changes or live scratch')
}

pub fn run_modern_checks() {
	mut manager := mmu.UatManager{}
	mut registered := unsafe { gpu.registration_manager() }
	saved := registered.uat
	registered.uat = unsafe { &manager }
	uat_mgr = unsafe { &manager }
	defer {
		registered.uat = saved
		uat_mgr = unsafe { nil }
	}
	check_modern_transport()
	check_modern_bind_staging_order()
	check_file_vm_names(mut manager)
	check_dormant_vm_capacity(mut manager)
	check_eager_vm_rollback(mut manager)
	check_modern_binding()
	check_modern_queue_and_object()
	check_gem_handle_storage()
	check_gem_file_names()
	check_gem_close_semantics()
	run_advice_checks()
	run_modern_scs_checks()
	assert params.timestamp_ns(24_000_003, 24_000_000) == 1_000_000_125
	assert params.timestamp_ns(1_000_003, 1_000_000) == 1_000_003_000
}

fn create_wire_gem(device &drm.DrmDevice, client u64, modern bool) (int, u32) {
	if modern {
		mut request := asahi.GemCreate{size: 0x4001, handle: 0xfeed}
		usercopy.configure(unsafe { u64(&request) }, sizeof(request), -1)
		code := drm.invoke(device, client, asahi.gem_create, sizeof(request), 3, unsafe { voidptr(&request) })
		assert request.size == 0x4001
		return code, request.handle
	}
	mut request := ioctl.DrmAsahiGemCreate{size: 0x4001, handle: 0xfeed}
	usercopy.configure(unsafe { u64(&request) }, sizeof(request), -1)
	code := drm.invoke(device, client, ioctl.drm_asahi_gem_create, sizeof(request), 3, unsafe { voidptr(&request) })
	assert request.size == 0x4001
	return code, request.handle
}

fn check_gem_handle_storage() {
	driver := drm.DrmDriver{ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle}
	device := drm.DrmDevice{driver: unsafe { &driver }}
	client := u64(0x4c01)
	memory.assert_released()
	for modern in [false, true]! {
		for _ in 0 .. 64 {
			mut file := GpuFile{ioctl_abi: if modern { modern_ioctl_abi } else { legacy_ioctl_abi },
				objects: Objects{table: bo.new_table(true)}}
			file_map[client] = unsafe { &file }
			before := gem.creates()
			memory.fail_allocations(true)
			first_error, unchanged := create_wire_gem(&device, client, modern)
			assert first_error == -12 && unchanged == 0xfeed && gem.creates() == before
			assert gem.live() == 0 && memory.outstanding() == 0 && !file.lock.is_held()
			memory.fail_allocations(false)
			first_code, first := create_wire_gem(&device, client, modern)
			assert first_code == 0 && first == 1 && memory.outstanding() == 1
			memory.fail_allocations(true)
			calls := memory.calls()
			second_code, second := create_wire_gem(&device, client, modern)
			assert second_code == 0 && second == first + 1 && memory.calls() == calls
			growth_error, still_unchanged := create_wire_gem(&device, client, modern)
			assert growth_error == -12 && still_unchanged == 0xfeed && gem.creates() == before + 2
			assert gem.live() == 2 && memory.outstanding() == 1 && !file.lock.is_held()
			memory.fail_allocations(false)
			third_code, third := create_wire_gem(&device, client, modern)
			assert third_code == 0 && third == second + 1 && gem.live() == 3
			assert memory.outstanding() == 1, 'growth must release the previous table'
			for handle in [first, second, third]! {
				object := file.objects.get_ref(handle) or { panic('published GEM handle disappeared') }
				assert object.handle == 0 && object.references == 2 && object.size == 0x8000
				gem.unref(object)
			}
			file_map.delete(client)
			assert file.close() && gem.live() == 0
			memory.assert_released()
		}
	}
	println('AGX GEM handle storage: 256 first/growth failures across both ABIs preserve request outputs and existing handles. Spare capacity, retries and close release pass.')
}

fn check_gem_file_names() {
	driver := drm.DrmDriver{features: drm.driver_gem, ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle, gem_close_request: close_gem_request}
	device := drm.DrmDevice{driver: unsafe { &driver }, driver_data: unsafe { voidptr(gpu.registration_manager()) }}
	first_key, second_key := u64(0x4c02), u64(0x4c03)
	first_fd, second_fd := voidptr(first_key), voidptr(second_key)
	proc.enable_owner(true)
	defer { proc.enable_owner(false) }
	for _ in 0 .. 64 {
		shared := gem.create(0xabc0)
		assert (gem_import_handler(&device, first_fd, shared) or { panic('early PRIME import') }) == 1
		assert (gem_import_handler(&device, second_fd, shared) or { panic('second PRIME import') }) == 1
		assert ioctl_abi_handle(&device, first_fd) == 0 && ioctl_abi_handle(&device, second_fd) == 0
		modern_code, modern_name := create_wire_gem(&device, first_key, true)
		legacy_code, legacy_name := create_wire_gem(&device, second_key, false)
		assert modern_code == 0 && legacy_code == 0 && modern_name == 2 && legacy_name == 2
		for expected in [u32(3), 4]! {
			code, name := create_wire_gem(&device, first_key, true)
			assert code == 0 && name == expected
		}
		old := gem_export_handler(&device, first_fd, 2) or { panic('original export') }
		other := gem_export_handler(&device, second_fd, 2) or { panic('second file export') }
		assert voidptr(old) != voidptr(other)
		mut first := lookup_file(first_fd) or { panic('first file') }
		old_offset := first.authorize_mmap(2) or { panic('original mmap offset') }
		assert first.admit_mmap_range(old_offset, old.size, true) == 0
		memory.fail_allocations(true)
		assert (gem_import_handler(&device, first_fd, shared) or { panic('repeat PRIME import') }) == 1
		assert gem_import_handler(&device, first_fd, other) == none
		assert shared.references == 3 && other.references == 2
		assert close_wire_gem(&device, first_key, 2, 0) == 0 && old.references == 2
		assert gem_export_handler(&device, first_fd, 2) == none
		assert gem_export_handler(&device, first_fd, old.handle) == none
		reuse_code, reused := create_wire_gem(&device, first_key, true)
		memory.fail_allocations(false)
		assert reuse_code == 0 && reused == 2
		fresh := gem_export_handler(&device, first_fd, reused) or { panic('replacement export') }
		assert voidptr(fresh) != voidptr(old) && voidptr(fresh) != voidptr(other)
		fresh_offset := first.authorize_mmap(reused) or { panic('replacement mmap offset') }
		assert fresh_offset != old_offset && first.admit_mmap_range(old_offset, old.size, true) == -13
		assert first.retain_mmap_range(old_offset, old.size)
		first.release_mmap_range(old_offset)
		first.release_mmap_range(old_offset)
		assert !first.retain_mmap_range(old_offset, old.size) && old.references == 1
		assert (gem_import_handler(&device, first_fd, other) or { panic('PRIME import retry') }) == 5
		assert close_wire_gem(&device, first_key, 1, 0) == 0
		release_handle(&device, first_fd)
		release_handle(&device, second_fd)
		for object in [old, other, fresh, shared]! { gem.unref(object) }
		assert gem.live() == 0
		memory.assert_released()
	}
	println('AGX G13 GEM handles: 64 independent file pairs preserve early PRIME imports across ABI selection, reuse closed names, and retain original mmap and export owners')
}

fn close_wire_gem(device &drm.DrmDevice, client u64, handle u32, pad u32) int {
	request := ioctl.DrmGemClose{handle: handle, pad: pad}
	usercopy.configure(unsafe { u64(&request) }, sizeof(request), -1)
	return drm.invoke(device, client, ioctl.drm_ioctl_gem_close, sizeof(request), 1, unsafe { voidptr(&request) })
}

fn check_gem_close_semantics() {
	driver := drm.DrmDriver{features: drm.driver_gem, ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle, gem_close_request: close_gem_request}
	device := drm.DrmDevice{driver: unsafe { &driver }, driver_data: unsafe { voidptr(gpu.registration_manager()) }}
	client := u64(0x4c04)
	assert close_wire_gem(&device, client, 1, 0) == -22 && lookup_file(voidptr(client)) == none
	for abi in [u32(0), legacy_ioctl_abi, modern_ioctl_abi]! {
		check_short_gem_close(&device, client, abi)
		for _ in 0 .. 64 {
			mut pt := pgtable.UatPgtable{}
			mut vm := mmu.UatContext{id: 1, vm_id: 1, pgtable: unsafe { &pt }}
			mut file := GpuFile{ioctl_abi: abi, vms: [unsafe { &vm }], objects: Objects{table: bo.new_table(true)}}
			file_map[client] = unsafe { &file }
			object := gem.create(7)
			handle := file.objects.add_created(object)
			assert handle == 1 && file.ioctl_gem_bind(bind(handle, 1, 0x4000)) == 0
			legacy := abi == legacy_ioctl_abi
			missing := if legacy { -2 } else { -22 }
			for absent in [u32(0), 2, ~u32(0)]! {
				assert close_wire_gem(&device, client, absent, 0) == missing
			}
			assert object.references == 2 && pt.unmaps == 0
			gpu.fail_mapping_checks(1)
			if legacy {
				assert close_wire_gem(&device, client, handle, 0xffffffff) == -22
				assert object.references == 2 && pt.unmaps == 0
				assert close_wire_gem(&device, client, handle, 0) == -5
			} else {
				assert close_wire_gem(&device, client, handle, 0xffffffff) == 0
			}
			assert file.ioctl_abi == abi && file.objects.get_ref(handle) == none
			assert pt.unmaps == 1 && object.references == 1 && vm.closed_mappings_pending
			assert close_wire_gem(&device, client, handle, 0) == missing
			assert file.mappings.len == 1 && file.mappings[0].retiring
			reap_open_detached_g13_queues()
			assert pt.unmaps == 1 && !vm.closed_mappings_pending && file.mappings.len == 0
			file_map.delete(client)
			assert file.close() && gem.live() == 0
			memory.assert_released()
		}
	}
	println('AGX G13 GEM_CLOSE: 192 wire cases cover missing handles, padding, and delayed GPU mapping retirement across both ABIs and before ABI selection')
}

fn check_short_gem_close(device &drm.DrmDevice, client u64, abi u32) {
	mut file := GpuFile{ioctl_abi: abi, objects: Objects{table: bo.new_table(true)}}
	file_map[client] = unsafe { &file }
	handle := file.objects.add_created(gem.create(7))
	assert handle != 0
	buffer := unsafe { voidptr(&handle) }
	usercopy.configure(u64(buffer), sizeof(handle), -1)
	assert drm.invoke(device, client, ioctl.drm_ioctl_gem_close, sizeof(handle), 1, buffer) == 0
	assert file.ioctl_abi == abi && file.objects.get_ref(handle) == none
	file_map.delete(client)
	assert file.close() && gem.live() == 0
	memory.assert_released()
}

fn check_file_vm_names(mut manager mmu.UatManager) {
	binds_before := manager.vm_binds
	mut first, mut second := GpuFile{}, GpuFile{}
	mut old_pt, mut new_pt := pgtable.UatPgtable{}, pgtable.UatPgtable{}
	mut old := mmu.UatContext{ id: 17, identity: mmu.new_identity(), pgtable: unsafe { &old_pt } }
	mut other := mmu.UatContext{ id: 18, identity: mmu.new_identity() }
	mut sibling := mmu.UatContext{ id: 20, identity: mmu.new_identity() }
	mut replacement := mmu.UatContext{ id: 19, identity: mmu.new_identity(), pgtable: unsafe { &new_pt } }
	mut request := ioctl.DrmAsahiVmCreate{ kernel_start: 0x100000000, kernel_end: 0x120000000 }
	manager.next_context = unsafe { &old }
	assert first.ioctl_vm_create(unsafe { &request }) == 0 && request.vm_id == 1
	manager.next_context = unsafe { &other }
	mut modern := asahi.VmCreate{ kernel_start: request.kernel_start, kernel_end: request.kernel_end }
	assert second.ioctl_modern_vm_create(unsafe { &modern }) == 0 && modern.vm_id == 1
	assert first.find_vm(17) == none && second.find_vm(18) == none
	assert (second.find_vm(1) or { panic('second file VM') }).id == 1
	manager.next_context = unsafe { &sibling }
	assert first.ioctl_vm_create(unsafe { &request }) == 0 && request.vm_id == 2

	mut queue := ioctl.DrmAsahiQueueCreate{ vm_id: 1, queue_caps: ioctl.asahi_queue_cap_compute }
	assert first.ioctl_queue_create(unsafe { &queue }) == 0
	assert first.queues[0].vm_id == old.id && first.g13_queues[0].vm_id == old.id
	assert first.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{ vm_id: 1 }) == 0
	assert first.find_vm(1) == none && !old.destroyed
	assert (first.find_owned_vm(old.id) or { panic('old queue VM') }).identity == old.identity

	request.vm_id = 99
	assert first.ioctl_vm_create(unsafe { &request }) == -12 && request.vm_id == 99
	assert manager.vm_binds == binds_before
	manager.next_context = unsafe { &replacement }
	assert first.ioctl_vm_create(unsafe { &request }) == 0 && request.vm_id == 1
	assert (first.find_vm(1) or { panic('reused file VM name') }).id == replacement.id
	assert first.queues[0].vm_id == old.id && replacement.id != old.id && !old.destroyed
	assert !old.is_bound() && !replacement.is_bound()

	mut object := ioctl.DrmAsahiGemCreate{ size: 0x4000, vm_id: 1, flags: ioctl.asahi_gem_vm_private }
	assert first.ioctl_gem_create(unsafe { &object }) == 0
	mut bind := ioctl.DrmAsahiGemBind{ vm_id: 1, handle: object.handle, flags: ioctl.asahi_bind_read, range: 0x4000, addr: 0x4000 }
	checks := gpu.mapping_checks()
	assert first.ioctl_gem_bind(unsafe { &bind }) == 0
	assert gpu.mapping_checks() == checks + 1 && !replacement.is_bound()
	assert first.mappings[0].vm_id == replacement.id && first.mappings[0].obj.vm_private_identity == replacement.identity
	assert old_pt.maps == 0 && new_pt.maps == 1
	unbind := ioctl.DrmAsahiGemBind{ vm_id: 1, op: ioctl.asahi_bind_op_unbind, range: bind.range, addr: bind.addr }
	// The replacement VM's job does not hold the binding (Asahi G13).
	replacement.inflight = 1
	assert first.ioctl_gem_bind(&unbind) == 0 && new_pt.unmaps == 1 && old_pt.unmaps == 0
	replacement.inflight = 0
	assert gpu.mapping_checks() == checks + 2
	assert first.ioctl_gem_bind(unsafe { &bind }) == 0
	assert manager.bind_context(&replacement) == 1 && replacement.is_bound()
	new_pt.tlb_asid = 6
	assert first.ioctl_gem_bind(&unbind) == 0 && new_pt.unmaps == 2 && old_pt.unmaps == 0
	assert gpu.mapping_checks() == checks + 4
	assert first.close() && second.close()
	assert old.destroyed && other.destroyed && sibling.destroyed && replacement.destroyed
	assert gem.live() == 0
	memory.assert_released()
	println('AGX VM names: per-file allocation, detached name reuse, failed creation and physical routing through queue, private GEM and VM_BIND passed')
	println('AGX VM publication: dormant edits and resident unbind use the page-table path without FwCtl')
}

fn check_dormant_vm_capacity(mut manager mmu.UatManager) {
	mut contexts := [96]mmu.UatContext{}
	mut file := GpuFile{}
	binds := manager.vm_binds
	mut request := asahi.VmCreate{kernel_start: 0x100000000, kernel_end: 0x120000000}
	for index in 0 .. contexts.len {
		context := unsafe { &contexts[index] }
		manager.next_context = context
		if file.vms.len == file.vms.cap {
			request.vm_id = 0xffffffff
			memory.fail_allocations(true)
			assert file.ioctl_modern_vm_create(&request) == -12 && request.vm_id == 0xffffffff
			memory.fail_allocations(false)
			assert file.vms.len == index && voidptr(manager.next_context) == voidptr(context)
		}
		assert file.ioctl_modern_vm_create(&request) == 0 && request.vm_id == u32(index + 1)
	}
	assert file.vms.len == 96 && manager.vm_binds == binds
	assert file.ioctl_vm_destroy(&ioctl.DrmAsahiVmDestroy{vm_id: 65}) == 0
	assert contexts[64].destroyed && file.find_vm(65) == none
	mut replacement := mmu.UatContext{}
	manager.next_context = unsafe { &replacement }
	assert file.ioctl_modern_vm_create(&request) == 0 && request.vm_id == 65
	assert (file.find_vm(66) or { panic('neighbor VM') }).id == 66
	assert file.close() && replacement.destroyed
	for context in contexts { assert context.destroyed }
	memory.assert_released()
	println('AGX VM admission: 96 dormant file VMs, fallible growth and reuse of public name 65 passed')
}

fn check_eager_vm_rollback(mut manager mmu.UatManager) {
	manager.handoff_abi = .g17_26_5
	defer { manager.handoff_abi = .v12_3 }
	mut file := GpuFile{}
	mut context := mmu.UatContext{}
	manager.next_context = unsafe { &context }
	mut request := asahi.VmCreate{vm_id: 77, kernel_start: 0x100000000, kernel_end: 0x120000000}
	assert file.ioctl_modern_vm_create(&request) == -12
	assert context.destroyed && file.vms.len == 0 && request.vm_id == 77
	assert file.close()
	memory.assert_released()
}

fn check_modern_queue_and_object() {
	gpu.available(true)
	gpu.set_running(true)
	mut pt := pgtable.UatPgtable{}
	mut vm := mmu.UatContext{ id: 1, vm_id: 1, pgtable: unsafe { &pt } }
	mut file := GpuFile{ vms: [unsafe { &vm }] }
	driver := drm.DrmDriver{ ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle }
	device := drm.DrmDevice{ driver: unsafe { &driver } }
	file_map[0x4444] = unsafe { &file }
	mut queue := asahi.QueueCreate{ vm_id: 1, priority: 1, usc_exec_base: 0x120000000 }
	usercopy.configure(unsafe { u64(&queue) }, sizeof(queue), -1)
	workqueue.fail_next()
	assert drm.invoke(&device, 0x4444, asahi.queue_create, sizeof(queue), 3, unsafe { voidptr(&queue) }) == -12
	assert queue.queue_id == 0
	workqueue.heap_next_record(true)
	assert drm.invoke(&device, 0x4444, asahi.queue_create, sizeof(queue), 3, unsafe { voidptr(&queue) }) == 0
	assert queue.queue_id == 1 && file.queues.len == 1
	assert file.queues[0].usc_base == queue.usc_exec_base && file.queues[0].caps == 5
	old_record := file.queues[0]
	captured := file.capture_submission_queue(queue.queue_id) or { panic('modern capture') }
	assert captured.usc_base == queue.usc_exec_base && captured.resources.has_file_references()
	destroy := asahi.QueueDestroy{ queue_id: queue.queue_id, pad: 0xffffffff }
	usercopy.configure(unsafe { u64(&destroy) }, sizeof(destroy), -1)
	assert drm.invoke(&device, 0x4444, asahi.queue_destroy, sizeof(destroy), 1, unsafe { voidptr(&destroy) }) == 0
	assert file.capture_submission_queue(queue.queue_id) == none
	assert !captured.resources.released, 'captured modern queue must survive name deletion'
	assert file.queues.len == 0 && file.g13_queues.len == 1
	assert C.__asan_address_is_poisoned(old_record) != 0, 'capture owns only the physical queue'
	mut replacement := asahi.QueueCreate{vm_id: 1, usc_exec_base: 0x160000000}
	usercopy.configure(unsafe { u64(&replacement) }, sizeof(replacement), -1)
	assert drm.invoke(&device, 0x4444, asahi.queue_create, sizeof(replacement), 3, unsafe { voidptr(&replacement) }) == 0
	assert replacement.queue_id == queue.queue_id && file.g13_queues.len == 2, 'a pinned old queue must not reserve the name'
	fresh := file.capture_submission_queue(replacement.queue_id) or { panic('replacement capture') }
	assert fresh.usc_base == replacement.usc_exec_base && voidptr(fresh.resources) != voidptr(captured.resources)
	mut old := unsafe { captured.resources }
	old.failures = 1
	release_submission_queue(captured)
	reap_open_detached_g13_queues()
	assert file.g13_queues.len == 2 && !old.released && !fresh.resources.released
	reap_open_detached_g13_queues()
	assert old.released && old.record_disposed && !fresh.resources.released
	assert file.queues.len == 1 && file.g13_queues.len == 1
	release_submission_queue(fresh)
	usercopy.configure(unsafe { u64(&destroy) }, sizeof(destroy), -1)
	assert drm.invoke(&device, 0x4444, asahi.queue_destroy, sizeof(destroy), 1, unsafe { voidptr(&destroy) }) == 0
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
	println('AGX modern queue/GEM ioctls: failed creation returns its name, replacement reuses a pinned queue name, retirement retries the old owner, and rounded objects keep wire output semantics')
}
