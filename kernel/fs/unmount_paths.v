// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import lib
import proc

// A copied namespace resolves saved cwd/root identities to its own Mount.
// A genuinely foreign route absent from that table still names the original
// permanent object. Only empty boot-root contexts need inode fallback.
// All nested locks are try-locks: callers hold the process table lock, while
// namespace copying and thread publication may acquire locks in other orders.
fn unmount_directory_uses(directory voidptr, context &lib.MountContext,
	ns &proc.Namespace, entry &Mount, boot_root bool) bool {
	if ns == unsafe { nil } { return false }
	identity := lib.mount_context_top(context)
	if identity != unsafe { nil } {
		if unsafe { &Mount(identity) }.id != entry.id { return false }
	} else if !boot_root || (directory != unsafe { nil }
		&& directory != voidptr(vfs_root) && directory != voidptr(entry.root)) {
		return false
	}
	mut table := if ns.data == unsafe { nil } { initial_mount_table }
		else { unsafe { &MountTable(ns.data) } }
	if !table.lock.test_and_acquire() { return true }
	for candidate in table.mounts {
		if candidate.id == entry.id {
			matches := voidptr(candidate) == voidptr(entry)
			table.lock.release()
			return matches
		}
	}
	table.lock.release()
	return identity == voidptr(entry)
}

// Borrow process and ThreadFS fields only while their owning locks protect
// them. A busy owner conservatively prevents this unmount attempt; it is not
// skipped. Published zombies have already released their filesystem state.
// This observes existing references; concurrent directory publication still
// needs the same admission protocol as writable open descriptions.
fn unmount_paths_in_use(entry &Mount) bool {
	boot_root := entry.parent.depth == 0 && entry.options != 'bind'
	proc.lock_table()
	defer { proc.unlock_table() }
	for pid := 1; pid < proc.max_pid; pid++ {
		mut owner := proc.process_at(pid)
		if owner == unsafe { nil } || owner.exit_published { continue }
		if !owner.fs_lock.test_and_acquire() { return true }
		// Executables retain the loader's actual attachment, even after a
		// namespace copy. Unlike cwd/root, do not resolve this route by id.
		held := (owner.exe_node != unsafe { nil }
			&& lib.mount_context_top(&owner.exe_mount) == voidptr(entry))
			|| unmount_directory_uses(owner.current_directory, &owner.current_mount,
			owner.ns.mnt, entry, boot_root)
			|| unmount_directory_uses(owner.root_directory, &owner.root_mount,
				owner.ns.mnt, entry, boot_root)
		owner.fs_lock.release()
		if held { return true }
		if !owner.threads_lock.test_and_acquire() { return true }
		for task in owner.threads {
			mut own := task.fs
			if own == unsafe { nil } { continue }
			if !own.lock.test_and_acquire() {
				owner.threads_lock.release()
				return true
			}
			inside := unmount_directory_uses(own.current_directory, &own.current_mount,
				own.mnt, entry, boot_root)
				|| unmount_directory_uses(own.root_directory, &own.root_mount,
					own.mnt, entry, boot_root)
			own.lock.release()
			if inside {
				owner.threads_lock.release()
				return true
			}
		}
		owner.threads_lock.release()
	}
	return false
}
