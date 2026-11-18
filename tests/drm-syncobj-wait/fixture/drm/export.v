// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import errno
import file
import memory
import proc
import resource

pub fn run_export_reservation_checks() {
	file.run_fd_reservation_checks()
	check_prime_descriptors()
	mut checks := 0
	for _ in 0 .. 200 {
		memory.reset(); proc.reset()
		obj := make_object(0); fence := make_fence(); syncobj.replace_fence(obj, fence)
		empty := make_object(0)
		mut request := ioctl.DrmSyncobjHandle{}
		for flags in [u32(0), 1]! {
			for missing in [u32(0), ~u32(0)]! {
				request = ioctl.DrmSyncobjHandle{ handle: missing, flags: flags, fd: -123 }
				assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == if flags == 0 { -22 } else { -2 }; checks++
				assert request.fd == -123; file.assert_reservations(0)
			}
		}
		request = ioctl.DrmSyncobjHandle{ handle: empty.handle, flags: 1, fd: -123 }
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -22; checks++
		file.assert_reservations(0)
		// Keep an invisible low slot while exporting. Neither export nor an
		// ordinary duplicate may steal it; cancellation makes it reusable.
		mut held := file.FdReservation{}
		assert (file.reserve_fd(unsafe { nil }, unsafe { &held }) or { panic('held') }) == 0
		number := export_object(11, obj.handle, 1); assert number == 1; checks++
		duplicate := file.duplicate(number); assert duplicate == 2; checks++
		file.cancel_fd_reservation(unsafe { &held })
		opaque := export_object(11, obj.handle, 0); assert opaque == 0; checks++
		// Refusing adoption after constructing a real description must release
		// that reference while preserving the source wrapper and its owners.
		mut invalid := file.FdReservation{}
		mut borrowed := file.fd_from_fdnum(unsafe { nil }, opaque) or { panic('borrowed') }
		mut res := borrowed.handle.resource
		owners := memory.outstanding(); descriptions := file.outstanding()
		if _ := file.fdnum_create_from_reserved_resource(unsafe { &invalid }, mut res, resource.o_cloexec) { assert false }; checks++
		assert errno.get() == errno.einval && memory.outstanding() == owners && file.outstanding() == descriptions
		assert !proc.current_thread().process.fds_lock.is_held()
		borrowed.unref()
		file.close(number); file.close(duplicate); file.close(opaque)
		assert memory.outstanding() == 0 && file.outstanding() == 0
		mut numbers := [32]int{}
		for index in 0 .. 32 { numbers[index] = export_object(11, obj.handle, 0); assert numbers[index] == index; checks++ }
		attempts := memory.attempts()
		memory.fail_next()
		for source in [obj.handle, empty.handle, u32(0), ~u32(0)]! {
			request = ioctl.DrmSyncobjHandle{ handle: source, flags: 1, fd: -123 }
			assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -24; checks++
			assert request.fd == -123 && memory.attempts() == attempts
			file.assert_reservations(0)
		}
		request = ioctl.DrmSyncobjHandle{ handle: 0, fd: -123 }
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -22; checks++
		request = ioctl.DrmSyncobjHandle{ handle: obj.handle, fd: -123 }
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -24; checks++
		for reserved in [u32(1), ~u32(0)]! {
			request = ioctl.DrmSyncobjHandle{ handle: 0, flags: 1, pad: reserved, fd: -123 }
			assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -22; checks++
			request = ioctl.DrmSyncobjHandle{ handle: 0, flags: 4, fd: -123 }
			assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -22; checks++
		}
		assert memory.attempts() == attempts
		// Full-table refusal did not consume OOM. The next available slot
		// survives private creation failure and is reused on recovery.
		file.close(numbers[17]); numbers[17] = -1
		request = ioctl.DrmSyncobjHandle{ handle: obj.handle, fd: -123 }
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == -12; checks++
		assert request.fd == -123; file.assert_reservations(0)
		request = ioctl.DrmSyncobjHandle{ handle: obj.handle, flags: 1, fd: -123 }
		assert ioctl_syncobj_handle_to_fd(voidptr(11), &request) == 0 && request.fd == 17; checks++
		file.close(int(request.fd))
		for number_to_close in numbers { if number_to_close >= 0 { file.close(number_to_close) } }
		assert !syncobj.is_signaled(fence)
		assert file.outstanding() == 0 && memory.outstanding() == 0
		file.assert_reservations(0)
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset(); proc.reset()
	}
	println('DRM export reservations: ${checks} checks; branch-specific validation, invisible slot exclusion, full-table/OOM precedence, unchanged outputs, missing handles/fences, duplicate exports and complete slot/owner recovery passed')
}
