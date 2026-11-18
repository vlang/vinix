// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.gem
import drm.ioctl
import drm.syncobj
import file
import memory
import proc
import sched
import usercopy

__global prime_signal_on_yield &syncobj.DmaFence = unsafe { nil }

fn complete_prime_fence(attempt u32) {
	assert attempt == 1 && !prime_exported.lock.is_held()
	syncobj.signal_error(prime_signal_on_yield, -5)
}

fn prime_access_result(mut fd file.FD, flags u64) int {
	address := unsafe { u64(&flags) }
	usercopy.allow(address, sizeof(flags))
	return prime_fd_ioctl(mut fd, 0x40086200, address)
}

fn prime_import_result(mut fd file.FD, flags u32, number i32) int {
	request := ioctl.DmaBufImportSyncFile{flags: flags, fd: number}
	address := unsafe { u64(&request) }
	usercopy.allow(address, sizeof(request))
	result := prime_fd_ioctl(mut fd, 0x40086203, address)
	assert request.flags == flags && request.fd == number
	assert usercopy.reads == 1 && usercopy.writes == 0
	return result
}

fn check_prime_reservation_waits() {
	memory.reset()
	proc.reset()
	mut object := gem.create(7)
	object.file_scoped = true
	prime_exported = unsafe { object }
	driver := DrmDriver{gem_export: prime_export, gem_import: prime_import}
	device := DrmDevice{driver: unsafe { &driver }}
	mut request := ioctl.DrmPrimeHandle{handle: 7, fd: -1}
	assert ioctl_prime_handle_to_fd(&device, voidptr(11), &request) == 0
	first_fd := request.fd
	assert ioctl_prime_handle_to_fd(&device, voidptr(12), &request) == 0
	second_fd := request.fd
	mut source := file.fd_from_fdnum(unsafe { nil }, first_fd) or { panic('first PRIME descriptor') }
	mut alias := file.fd_from_fdnum(unsafe { nil }, second_fd) or { panic('second PRIME descriptor') }
	assert prime_fd_ioctl(mut source, 0x40086203, 0) == -14
	assert prime_import_result(mut source, 1, second_fd) == -22
	assert prime_import_result(mut source, 3, -1) == -22
	assert prime_import_result(mut source, 0, -1) == -22
	assert prime_import_result(mut source, 4, -1) == -22

	prime_storage := memory.outstanding()
	first := make_fence()
	second := make_fence()
	timeline := make_object(0)
	first_link := remember_fence(syncobj.reserve_chain() or { panic('first link') })
	second_link := remember_fence(syncobj.reserve_chain() or { panic('second link') })
	assert syncobj.add_chain_point(timeline, first_link, first, 5)
	assert syncobj.add_chain_point(timeline, second_link, second, 10)
	chain_storage := memory.outstanding() - prime_storage
	chain_fd := create_sync_file_fd(second_link) or { panic('chain sync file') }
	before_import := memory.outstanding()
	memory.fail_in(1)
	assert prime_import_result(mut source, 1, i32(chain_fd)) == -12
	assert memory.outstanding() == before_import && object.prime_fences == unsafe { nil }
	assert prime_import_result(mut source, 1, i32(chain_fd)) == 0
	assert memory.outstanding() == before_import + 2
	file.close(chain_fd)

	sched.reset(unsafe { nil })
	assert prime_access_result(mut alias, 1) == 0 && sched.polls == 0
	assert prime_access_result(mut alias, 6) == 0 && sched.polls == 0
	leaf_fd := create_sync_file_fd(first) or { panic('first sync file') }
	before_upgrade := memory.outstanding()
	assert prime_import_result(mut source, 1, i32(leaf_fd)) == 0
	assert prime_import_result(mut source, 3, i32(leaf_fd)) == 0
	assert memory.outstanding() == before_upgrade
	file.close(leaf_fd)
	gem.unref(object)

	prime_signal_on_yield = first
	sched.reset(complete_prime_fence)
	assert prime_access_result(mut alias, 1) == 0 && sched.polls == 1
	assert !syncobj.is_signaled(second)
	assert prime_access_result(mut alias, 6) == 0 && sched.polls == 1
	proc.private_signal(false)
	sched.reset(unsafe { nil })
	assert prime_access_result(mut alias, 2) == -proc.interrupted_errno && sched.polls == 0
	proc.private_signal(true)
	prime_signal_on_yield = second
	sched.reset(complete_prime_fence)
	assert prime_access_result(mut alias, 3) == 0 && sched.polls == 1
	assert object.prime_fences == unsafe { nil }
	assert memory.outstanding() == prime_storage + chain_storage

	last := make_fence()
	last_fd := create_sync_file_fd(last) or { panic('last sync file') }
	assert prime_import_result(mut source, 2, i32(last_fd)) == 0
	file.close(last_fd)
	source.unref()
	alias.unref()
	file.close(first_fd)
	assert object.references == 1 && object.prime_fences != unsafe { nil }
	file.close(second_fd)
	prime_exported = unsafe { nil }
	assert gem.live() == 0 && file.outstanding() == 0 && memory.outstanding() == chain_storage
	assert !syncobj.is_signaled(last)
	syncobj.signal(last)
	prime_signal_on_yield = unsafe { nil }
	sched.reset(unsafe { nil })
	usercopy.allow(0, 0)
	clear()
	memory.reset()
	proc.reset()
	println('DRM PRIME reservation waits: shared re-exports, import rollback, read/write filtering, signals and final close passed')
}
