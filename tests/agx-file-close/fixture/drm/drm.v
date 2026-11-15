@[has_globals]
module drm

import drm.gem
import drm.ioctl

pub struct DrmDriver {
pub:
	gem_export fn (&DrmDevice, voidptr, u32) ?&gem.GemObject = unsafe { nil }
	gem_export_put fn (&DrmDevice, &gem.GemObject) = unsafe { nil }
}

pub struct DrmDevice {
pub:
	driver &DrmDriver = unsafe { nil }
}

__global exported &gem.GemObject = unsafe { nil }
__global export_calls = 0
__global export_puts = 0
__global prime_fds = 0

fn export_object(_dev &DrmDevice, _handle voidptr, id u32) ?&gem.GemObject {
	export_calls++
	if exported == unsafe { nil } || exported.handle != id { return none }
	gem.ref_obj(exported)
	return exported
}

fn put_object(_dev &DrmDevice, object &gem.GemObject) {
	export_puts++
	gem.unref(object)
}

fn create_prime_fd(_dev &DrmDevice, object &gem.GemObject, _flags u32) ?int {
	prime_fds++
	// Inject successful fd creation followed by immediate close. The real
	// fd owns this reference; private refusal must never reach this service.
	gem.unref(object)
	return 17
}

pub fn check_prime_policy() {
	custom := DrmDriver{ gem_export: export_object, gem_export_put: put_object }
	standard := DrmDriver{ gem_export: export_object }
	for driver in [custom, standard]! {
		device := DrmDevice{ driver: &driver }
		mut object := gem.GemObject{ handle: 7, vm_private_identity: 99 }
		exported = &object
		for _ in 0 .. 200 {
			mut request := ioctl.DrmPrimeHandle{ handle: 7, fd: -1 }
			before := prime_fds
			assert ioctl_prime_handle_to_fd(&device, voidptr(1), &request) == -22
			assert prime_fds == before && object.references == 1 && request.fd == -1
		}
		object.vm_private_identity = 0 // separate shareable-object case
		mut request := ioctl.DrmPrimeHandle{ handle: 7, flags: ioctl.drm_cloexec | ioctl.drm_rdwr, fd: -1 }
		assert ioctl_prime_handle_to_fd(&device, voidptr(1), &request) == 0
		assert request.fd == 17 && object.references == 1
		before := export_calls
		request.flags = 0x80000000
		assert ioctl_prime_handle_to_fd(&device, voidptr(1), &request) == -22
		assert export_calls == before && object.references == 1
		request.flags = 0
		request.handle = 8
		assert ioctl_prime_handle_to_fd(&device, voidptr(1), &request) == -2
		assert object.references == 1
	}
	exported = unsafe { nil }
	assert export_puts == 200 && prime_fds == 2
	println('DRM PRIME private policy: 400 EINVAL refusals return owned export references via custom/default put before fd creation; shareable export remains available')
}
