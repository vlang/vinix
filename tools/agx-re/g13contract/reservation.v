// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_fd_reservation_contract(reservations string, files string, process string) ! {
	require(process.contains('fds_reserved             voidptr'), 'Process reservation head missing')!
	reserve := section(reservations, 'pub fn reserve_fd(', '// Caller holds', 'Native number reservation')!
	require_order(reserve, ['node.process != unsafe { nil }', 'process.fds_lock.acquire()', 'defer { process.fds_lock.release() }',
		'process.rlimits[proc.rlimit_nofile].cur', 'fd_number_reserved_locked(process, number)', 'grow_fd_table(mut process, number)',
		'errno.set(errno.enomem)', 'node.process = process', 'node.number = number', 'node.next =',
		'process.fds_reserved = voidptr(reservation)', 'return number', 'errno.set(errno.emfile)'], 'Reserve under table lock before exposing a node')!
	require(!reserve.contains('process.fds[number] ='), 'A reservation must stay invisible to descriptor readers')!
	remove := section(reservations, 'fn remove_fd_reservation_locked(', 'pub fn cancel_fd_reservation(', 'Native borrowed-link removal')!
	require_order(remove, ['voidptr(node) == voidptr(reservation)', 'target.fds_reserved = voidptr(node.next)',
		'previous.next = node.next', 'node.process = unsafe { nil }; node.number = -1; node.next = unsafe { nil }', 'return true'],
		'Unlink and clear borrowed storage before leaving scope')!
	install := section(reservations, 'pub fn fdnum_install_reserved_fd(', 'pub fn fdnum_create_from_reserved_resource(', 'Native reserved adoption')!
	require_order(install, ['process.fds_lock.acquire()', 'defer { process.fds_lock.release() }',
		'process.fds[number] != unsafe { nil }', '!fd_number_reserved_locked(process, number)',
		'!descriptor_mount_admitted(fd)', '!remove_fd_reservation_locked(process, reservation)',
		'process.fds[number] = voidptr(fd)', 'return number'], 'Reserved adoption clears links before table publication')!
	require(!install.contains('fd.unref(') && !install.contains('grow_fd_table('), 'Installation must not allocate or close under the table lock')!
	require_order(reservations.all_after('pub fn fdnum_create_from_reserved_resource('),
		['fd_create_from_resource(mut res, flags)', 'fdnum_install_reserved_fd(reservation, fd)', 'fd.unref(); return none'],
		'Failed adoption releases the created description after installation unlocks')!
	require(files.contains('process.fds[i] == unsafe { nil } && !fd_number_reserved_locked(process, i)')
		&& files.contains('if fd_number_reserved_locked(process, oldfd) {')
		&& files.contains('if fd_number_reserved_locked(process, number) { continue }'), 'All existing number creators must exclude reservations')!
}

fn check_export_reservation_reference(reference string, files string) ! {
	export := section(reference, 'static int drm_syncobj_export_sync_file(', '/**\n * drm_syncobj_open', 'Linux sync-file export ordering')!
	require_order(export, ['get_unused_fd_flags(O_CLOEXEC)', 'if (fd < 0)', 'return fd', 'drm_syncobj_find_fence(',
		'sync_file_create(fence)', 'if (!sync_file)', 'ret = -EINVAL', 'fd_install(', '*p_fd = fd', 'put_unused_fd(fd)'], 'Linux source lookup follows number reservation')!
	find := section(reference, 'int drm_syncobj_find_fence(', 'EXPORT_SYMBOL(drm_syncobj_find_fence)', 'Linux source lookup errors')!
	require_order(find, ['drm_syncobj_find(file_private, handle)', 'if (!syncobj)', 'return -ENOENT'], 'Missing sync-file source is ENOENT')!
	allocate := section(files, 'static int alloc_fd(', 'int __get_unused_fd_flags(', 'Linux invisible descriptor reservation')!
	require_order(allocate, ['spin_lock(&files->file_lock)', 'error = -EMFILE', 'expand_files(files, fd)',
		'__set_open_fd(fd, fdt, flags & O_CLOEXEC)', 'rcu_access_pointer(fdt->fd[fd]) != NULL', 'spin_unlock(&files->file_lock)'], 'Linux reserves a number with no installed file')!
	require(files.contains('return -EBUSY;') && files.contains('__clear_open_fd(fd, fdt)'), 'Linux busy-slot or unused-slot retirement changed')!
}
