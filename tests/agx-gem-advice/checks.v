// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm
import drm.asahi
import drm.gem
import gpu.agx.mmu
import klock
import usercopy

__global advice_race_file &GpuFile = unsafe { nil }
__global advice_race_handle u32

fn C.__builtin_alloca(uint) voidptr

pub fn trace_advice() {
	mut wire := asahi.GemMadvise{}
	unsafe { C.printf(c'wire %u %llu %llu %llu %llu\n', u32(sizeof(wire)), u64(&wire.handle) - u64(&wire), u64(&wire.madv) - u64(&wire), u64(&wire.retained) - u64(&wire), u64(&wire.pad) - u64(&wire)) }
	for initial := u32(0); initial < 2; initial++ {
		for pattern := u32(0); pattern < 1024; pattern++ {
			mut object := gem.GemObject{vm_private_identity: 1, advice_dontneed: initial != 0}
			for step := u32(0); step < 10; step++ {
				retained := gem.advise_private(unsafe { &object }, pattern & (u32(1) << step) != 0) or { panic('resident advice') }
				C.printf(c'%u %u %u %u %u\n', initial, pattern, step, retained, u32(object.advice_dontneed))
			}
		}
	}
}

pub fn measure_advice() {
	mut file := unsafe { &GpuFile(C.__builtin_alloca(sizeof(GpuFile))) }
	unsafe { *file = GpuFile{} }
	object := gem.create(54)
	unsafe { object.vm_private_identity = 700 }
	file.objects.add_created(object)
	mut request := asahi.GemMadvise{handle: 54}
	for batch in 0 .. 4 {
		before_blocks, before_bytes := live_record_heap()
		for _ in 0 .. 10000 {
			request.madv ^= 1
			assert file.ioctl_modern_gem_madvise(unsafe { &request }) == 0
			assert request.retained == 1 && object.references == 1
		}
		after_blocks, after_bytes := live_record_heap()
		if batch != 0 {
			assert before_blocks == after_blocks && before_bytes == after_bytes
			println('gem-advice batch=${batch} operations=10000 retained_blocks=0 retained_bytes=0')
		}
	}
	assert file.close()
}

fn drop_advice_handle() {
	mut file := unsafe { advice_race_file }
	file.lock.acquire()
	object := file.objects.remove(advice_race_handle) or { panic('race handle') }
	file.lock.release()
	assert object.references == 2, 'advice must own a reference after releasing the file lock'
	gem.unref(object)
}

pub fn run_advice_checks() {
	mut cases := 0
	for private in [false, true]! { for external in [false, true]! {
		mut file := unsafe { &GpuFile(C.__builtin_alloca(sizeof(GpuFile))) }
		mut foreign := unsafe { &GpuFile(C.__builtin_alloca(sizeof(GpuFile))) }
		unsafe { *file = GpuFile{}; *foreign = GpuFile{} }
		object := gem.create(51)
		unsafe { object.vm_private_identity = if private { u64(700) } else { u64(0) }; object.external = external }
		contents := C.__builtin_alloca(64)
		unsafe { C.memset(contents, 0x5a, 64); object.phys_addr = u64(contents) }
		file.objects.add_created(object)
		mut vm := mmu.UatContext{inflight: 9}
		file.vms << &vm
		for owner in 0 .. 3 { for madv in [u32(0), 1, 2, ~u32(0)]! { for pad in [u32(0), 1]! {
			unsafe { object.advice_dontneed = madv == 0 }
			old_advice := object.advice_dontneed
			mut request := asahi.GemMadvise{handle: if owner == 2 { u32(999) } else { object.handle }, madv: madv, retained: 0xa5a5a5a5, pad: pad}
			lookups := object_ref_lookups
			code := if owner == 1 { foreign.ioctl_modern_gem_madvise(unsafe { &request }) } else { file.ioctl_modern_gem_madvise(unsafe { &request }) }
			bad_header := pad != 0 || madv > 1
			expected := if bad_header { -22 } else if owner != 0 { -2 } else if !private || external { -22 } else { 0 }
			assert code == expected, 'advice validation and ownership precedence'
			assert object_ref_lookups - lookups == if bad_header { 0 } else { 1 }, 'advice validation and ownership precedence'
			assert object.references == 1, 'advice lookup reference must be released on every exit'
			assert !file.lock.is_held() && !foreign.lock.is_held() && !object.lock.is_held()
			assert request.retained == if code == 0 { u32(1) } else { u32(0xa5a5a5a5) }
			assert object.advice_dontneed == if code == 0 { madv == 1 } else { old_advice }, 'advice state must change only on success'
			assert object.phys_addr == u64(contents)
			for index in 0 .. 64 { assert unsafe { (&u8(contents))[index] } == 0x5a, 'advice must retain resident contents' }
			cases++
		} } }
		vm.inflight = 0
		assert file.close() && foreign.close()
	} }
	assert cases == 96
	// The ioctl reference survives handle removal before the object lock.
	mut racing := unsafe { &GpuFile(C.__builtin_alloca(sizeof(GpuFile))) }
	unsafe { *racing = GpuFile{} }
	object := gem.create(52)
	unsafe { object.vm_private_identity = 700 }
	racing.objects.add_created(object)
	advice_race_file = unsafe { racing }; advice_race_handle = 52
	before := gem.live()
	klock.before_once(unsafe { &object.lock }, drop_advice_handle)
	mut advice := asahi.GemMadvise{handle: 52, madv: 1}
	assert racing.ioctl_modern_gem_madvise(unsafe { &advice }) == 0 && advice.retained == 1
	assert gem.live() == before - 1 && !racing.lock.is_held()
	assert racing.close()
	advice_race_file = unsafe { nil }
	check_advice_transport()
	println('GEM advice: 96 validation/ownership/state cases, handle removal during object-lock acquisition, resident contents and modern transport pass.')
}

fn check_advice_transport() {
	mut file := unsafe { &GpuFile(C.__builtin_alloca(sizeof(GpuFile))) }
	mut legacy := unsafe { &GpuFile(C.__builtin_alloca(sizeof(GpuFile))) }
	unsafe { *file = GpuFile{ioctl_abi: modern_ioctl_abi}; *legacy = GpuFile{ioctl_abi: legacy_ioctl_abi} }
	file_map[0xad01] = unsafe { file }; file_map[0xad02] = unsafe { legacy }
	driver := drm.DrmDriver{ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle}
	device := drm.DrmDevice{driver: unsafe { &driver }}
	object := gem.create(53)
	unsafe { object.vm_private_identity = 700 }
	file.objects.add_created(object)
	mut request := asahi.GemMadvise{handle: 53, madv: 1}
	usercopy.configure(unsafe { u64(&request) }, sizeof(request), -1)
	assert drm.invoke(&device, 0xad01, asahi.gem_madvise, sizeof(request), 3, unsafe { &request }) == 0
	assert request.retained == 1 && object.advice_dontneed && object.references == 1
	assert drm.invoke(&device, 0xad02, asahi.gem_madvise, sizeof(request), 3, unsafe { &request }) == -22
	request.madv = 0; request.retained = 0xabababab
	usercopy.configure(unsafe { u64(&request) }, sizeof(request), 8)
	assert drm.invoke(&device, 0xad01, asahi.gem_madvise, sizeof(request), 3, unsafe { &request }) == -14
	assert !object.advice_dontneed && request.retained == 0xabababab && object.references == 1
	request.madv = 1
	usercopy.fail_read_at(unsafe { u64(&request) } + 4)
	lookups := object_ref_lookups
	assert drm.invoke(&device, 0xad01, asahi.gem_madvise, sizeof(request), 3, unsafe { &request }) == -14
	assert object_ref_lookups == lookups && !object.advice_dontneed
	usercopy.fail_read_at(0)
	file_map.delete(0xad01); file_map.delete(0xad02)
	assert file.close() && legacy.close()
}
