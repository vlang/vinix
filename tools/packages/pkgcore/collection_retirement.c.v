// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn check_collection_root(parent int, name string, lease CollectionLease, device u64) ! {
	check_collection_root_owned(parent, name, lease, device, u32(C.geteuid()))!
}

fn check_collection_root_owned(parent int, name string, lease CollectionLease, device u64, owner u32) ! {
	info := owned_generation_directory(lease.directory, device, owner)!
	if info.st_mode & 0o022 != 0 { return error('unsafe obsolete generation root writable by other accounts; retain state and restore administrator-only write access before collection') }
	check_stage_name(parent, name, lease.directory_device, lease.directory_inode)!
}

// The caller holds the writer lock and this generation's exclusive lease.
// Keep the lease named until all other entries are gone, so earlier failures
// remain retryable. The complete inventory precedes the first unlink.
fn remove_collection_tree(parent int, root StageTarget, lease CollectionLease, nodes []StageDirectory) ! {
	check_collection_root(parent, root.name, lease, root.device)!
	check_collection_lease(lease)!
	for index := nodes.len - 1; index > 0; index-- {
		remove_stage_directory(lease.directory, parent, root, nodes, index)!
	}
	check_collection_root(parent, root.name, lease, root.device)!
	remove_retirement_leaves(lease.directory, 'lease')!
	check_collection_root(parent, root.name, lease, root.device)!
	check_collection_lease(lease)!
	if C.unlinkat(lease.directory, c'lease', 0) != 0 { return error('cannot retire obsolete generation lease; retain state and retry collection') }
	if C.unlinkat(parent, root.name.str, C.AT_REMOVEDIR) != 0 {
		return error('obsolete generation contents retired but empty directory removal failed; inspect storage and restore an empty regular lease under the writer lock before retrying collection')
	}
}
