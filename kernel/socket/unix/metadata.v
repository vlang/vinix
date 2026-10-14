// SPDX-License-Identifier: GPL-2.0-or-later
module unix

import resource
import stat

fn (mut this UnixSocket) path_xattr_backend() &resource.Resource {
	return this.namespace_resource
}

fn (mut this UnixSocket) path_xattrs_changed() {
	if this.namespace_resource == unsafe { nil } { return }
	this.stat.mode = this.namespace_resource.stat.mode
	this.stat.ctim = this.namespace_resource.stat.ctim
}

// bind retains the filesystem resource until the endpoint retires. Borrow it
// synchronously: the backend snapshots its ACL and matching owner/mode under
// its own locks, without taking the socket transport lock or creating a box.
fn (mut this UnixSocket) snapshot_permissions(mut acl []u8) ?resource.PermissionMetadata {
	if this.namespace_resource == unsafe { nil } {
		return resource.PermissionMetadata{this.stat.mode, this.stat.uid, this.stat.gid}
	}
	mut backing := this.namespace_resource
	return resource.permission_snapshot(mut backing, mut acl)
}

fn (mut this UnixSocket) chmod_mode(mode u32) ? {
	if this.namespace_resource == unsafe { nil } {
		this.stat.mode = (this.stat.mode & stat.ifmt) | (mode & 0o7777)
		return
	}
	mut backing := this.namespace_resource
	resource.set_mode(mut backing, mode)?
	this.stat.mode = backing.stat.mode
	this.stat.ctim = backing.stat.ctim
}

// Generic ownership/timestamp syscalls stage fields on the endpoint before
// calling persist_metadata. Transfer only those fields; namespace operations
// own the backing inode's identity and link count. Restore staged backing
// fields on error so an unsuccessful chown cannot affect later ACL checks.
fn (mut this UnixSocket) persist_metadata() ? {
	if this.namespace_resource == unsafe { nil } { return }
	mut backing := this.namespace_resource
	old := backing.stat
	backing.stat.mode = this.stat.mode
	backing.stat.uid = this.stat.uid
	backing.stat.gid = this.stat.gid
	backing.stat.atim = this.stat.atim
	backing.stat.mtim = this.stat.mtim
	backing.stat.ctim = this.stat.ctim
	resource.persist_metadata(mut backing) or {
		backing.stat.mode = old.mode
		backing.stat.uid = old.uid
		backing.stat.gid = old.gid
		backing.stat.atim = old.atim
		backing.stat.mtim = old.mtim
		backing.stat.ctim = old.ctim
		return none
	}
}
