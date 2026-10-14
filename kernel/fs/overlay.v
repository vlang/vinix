// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// overlay: one directory tree seen through another, as Linux's overlayfs
// presents it and as Docker's overlay2 storage driver mounts every container
// and image layer:
//
//	mount -t overlay overlay -o lowerdir=L1:L2,upperdir=U,workdir=W merged
//
// The merged tree shows U over L1 over L2. A name in a higher layer hides the
// same name below it, and a directory present in several layers shows all
// their entries. A character device numbered 0/0 in a layer is a whiteout: it
// hides the name below it. A directory with trusted.overlay.opaque=y hides the
// directories of its name below it. Without an upper directory the mount is
// read-only.
//
// Nothing is copied at mount time. An overlay node leads to the resource of
// the highest layer that has its name, so reading, mapping and running a file
// go straight to it. The first change to a lower file or directory copies it,
// and every directory above it, into the upper layer, and the node leads there
// from then on ("copy up"). Making, linking, renaming and removing names works
// in the upper layer, leaving a whiteout where a lower name has to stay
// hidden. A directory's merged entries are worked out the first time it is
// looked in. Renaming a directory that has lower entries fails with EXDEV,
// which is what Linux does without redirect_dir, and what `mv` and Docker's
// driver expect from it.
//
// The layers are assumed not to change under a mount, which is what Linux
// assumes too; Docker never changes them.
@[has_globals]
module fs

import errno
import kbudget
import katomic
import klock
import lib
import proc
import resource
import security
import stat

// Bound lazy layer population and other callbacks through stacked overlays.
const overlay_max_layer_depth = 8

struct OverlayFS {
mut:
	dev_id u64
	upper  &VFSNode = unsafe { nil }
	work   &VFSNode = unsafe { nil }
	lowers []&VFSNode
	staging_serial u64
	staging_owner u32
	work_next &OverlayFS = unsafe { nil }
	layer_depth int
}

// What an overlay node is made of.
pub struct OverlayEntry {
mut:
	fs &OverlayFS = unsafe { nil }
	// The name in the upper layer, once there is one.
	upper &VFSNode = unsafe { nil }
 // Kept until generic identity/ACL initialization commits the creation.
 rollback_whiteout &VFSNode = unsafe { nil }
 uncommitted bool
 staged bool
	// A directory's lower directories, highest first, down to the first
	// opaque one; for anything else, the lower file it shows while it has no
	// upper copy.
	lowers []&VFSNode
	// Some lower layer has this name, so removing it takes a whiteout.
	has_lower bool
	// A directory's merged entries have been worked out.
	populated bool
	// One node and resource reference for every upper/lower pointer.
	retained bool
	// A backing alias can copy up later. Release the exact resource acquired,
	// rather than whichever resource its node then happens to expose.
	upper_resource &resource.Resource = unsafe { nil }
	lower_resources []&resource.Resource
}

// One name while a directory is merged.
struct OverlayMerge {
mut:
	top        &VFSNode = unsafe { nil }
	from_upper bool
	whiteout   bool
	// A directory still taking in the directories of its name below.
	collecting bool
	has_lower  bool
	dirs       []&VFSNode
}

__global (
	// Every overlay change and merge. Taken after vfs_lock where both are.
	overlay_lock klock.Lock
)

fn (mut this OverlayFS) instantiate() &FileSystem {
	return &OverlayFS{
		lowers: []&VFSNode{}
	}
}

fn (mut this OverlayFS) populate(node &VFSNode) {}

fn (mut this OverlayFS) mount(parent &VFSNode, name string, source &VFSNode) ?&VFSNode {
	// Mounted through overlay_mount(), which gets the options.
	errno.set(errno.einval)
	return none
}

fn (mut this OverlayFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	overlay_lock.acquire()
	defer {
		overlay_lock.release()
	}
	mut dir := unsafe { parent }
	return overlay_create_locked(mut dir, name, mode) or { return unsafe { nil } }
}

fn (mut this OverlayFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	overlay_lock.acquire()
	defer {
		overlay_lock.release()
	}
	mut dir := unsafe { parent }
	return overlay_symlink_locked(mut dir, dest, target) or { return unsafe { nil } }
}

fn (mut this OverlayFS) link(parent &VFSNode, name string, mut old_node VFSNode) ?&VFSNode {
	overlay_lock.acquire()
	defer {
		overlay_lock.release()
	}
	mut dir := unsafe { parent }
	return overlay_link_locked(mut dir, name, mut old_node)
}

fn (mut this OverlayFS) rename(old_parent &VFSNode, old_name string, new_parent &VFSNode, new_name string, flags int) ? {
	// rename() hands overlay directories to overlay_rename() instead.
	errno.set(errno.exdev)
	return none
}

// ── Layers ───────────────────────────────────────────────────────────────────

pub fn is_whiteout(node &VFSNode) bool {
	return node != unsafe { nil } && node.resource != unsafe { nil }
		&& node.resource.stat.mode & stat.ifmt == stat.ifchr && node.resource.stat.rdev == 0
}

fn is_opaque(node &VFSNode) bool {
	if node == unsafe { nil } || node.resource == unsafe { nil }
		|| !stat.isdir(node.resource.stat.mode) {
		return false
	}
	// An unreadable marker must never turn into permission to merge lower data.
	return xattr_equals(node.resource, 'trusted.overlay.opaque', 'y') or { true }
}

// A name in a real directory, made as the kernel makes it, without the
// caller's permission checks: a copy up is done for the caller, whoever it is.
fn overlay_real_create(mut dir VFSNode, name string, mode u32, label_source &resource.Resource) ?&VFSNode {
 real := overlay_prepare_real_create(mut dir, name, mode, label_source)?
 publish_child(dir, name, real)
 return real
}

fn overlay_prepare_real_create(mut dir VFSNode, name string, mode u32, label_source &resource.Resource) ?&VFSNode {
	charge := proc.reserve_kernel(.file, 8192 + u64(name.len) * 2)?
 mut assigned := false
 defer { if !assigned { kbudget.release(charge) } }
 real_name := name.clone()
 mut real := dir.filesystem.create(dir, real_name, mode)
	if real == unsafe { nil } {
  unsafe { real_name.free() }
		if errno.get() == 0 {
			errno.set(errno.eio)
		}
		return none
	}
	real.kernel_charge = charge
 assigned = true
	// The upper path is independently reachable: inherit the final label
	// before exposing even a partially copied inode through that route.
	mut source := unsafe { label_source }
	mut target := real.resource
	security.mac_inherit(mut source, mut target) or {
		failure := errno.get()
		discard_created_node(mut real, dir)
		errno.set(failure)
		return none
	}
	if stat.isdir(mode) {
		real.create_dotentries(dir)
	}
	return real
}

fn overlay_real_symlink(mut dir VFSNode, dest string, name string, label_source &resource.Resource) ?&VFSNode {
 real := overlay_prepare_real_symlink(mut dir, dest, name, label_source)?
 publish_child(dir, name, real)
 return real
}

fn overlay_prepare_real_symlink(mut dir VFSNode, dest string, name string, label_source &resource.Resource) ?&VFSNode {
	charge := proc.reserve_kernel(.file, 8192 + u64(name.len) * 2)?
 mut assigned := false
 defer { if !assigned { kbudget.release(charge) } }
 real_name := name.clone()
 mut real := dir.filesystem.symlink(dir, dest, real_name)
	if real == unsafe { nil } {
  unsafe { real_name.free() }
		if errno.get() == 0 {
			errno.set(errno.eio)
		}
		return none
	}
	real.kernel_charge = charge
 assigned = true
	// The upper path is independently reachable: inherit the final label
	// before exposing even a partially copied inode through that route.
	mut source := unsafe { label_source }
	mut target := real.resource
	security.mac_inherit(mut source, mut target) or {
		failure := errno.get()
		discard_created_node(mut real, dir)
		errno.set(failure)
		return none
	}
	return real
}

// Take `name` out of a real directory. A directory is left with its entries
// map, which only whiteouts can still be in, and its namespace resource until
// node retirement. Overlay entries retain their own backing references.
fn overlay_dispose_real(mut real VFSNode) {
 if real.resource == unsafe { nil } { return }
 mut res := real.resource
 // A failed disk unlink may still leave this inode named. Keep its
 // reference and reservation until a safe cleanup is possible.
 res.unlink(voidptr(real)) or { return }
 overlay_release_unlinked_real(mut real)
}

// A successful backend rename already removed the replaced name. Share its
// ordinary retirement path without unlinking that name a second time.
fn overlay_release_unlinked_real(mut real VFSNode) {
 mut res := real.resource
 mode := res.stat.mode
 if stat.isdir(mode) {
  overlay_detach_work_locked(mut real)
  real.removed = true
  res.stat.nlink = 0
  real.directory_resource = true
 } else { release_resource_after_grace(res) }
 orphan_node(mut real, mode)
}
fn overlay_drop_real_locked(mut dir VFSNode, name string) {
 if name !in dir.children { return }
 mut real := unsafe { dir.children[name] }
 if real != unsafe { nil } { hold_parent(mut real) }
 remove_child(dir, name)
 if real != unsafe { nil } { overlay_dispose_real(mut real) }
}

// Drop the whiteouts an upper directory holds, before the directory goes.
fn overlay_drop_whiteouts_locked(mut dir VFSNode) {
	if dir.children == unsafe { nil } {
		return
	}
	mut names := dir.children.keys()
	defer {
		unsafe { names.free() }
	}
	for name in names {
		child := unsafe { dir.children[name] }
		if is_whiteout(child) {
			overlay_drop_real_locked(mut dir, name)
		}
	}
}

fn overlay_whiteout_locked(mut dir VFSNode, name string) ? {
	backing := device_by_name('null')
	if backing == unsafe { nil } {
		errno.set(errno.eio)
		return none
	}
	install_device_node(mut dir, name, stat.ifchr, 0, backing)?
}

fn overlay_prepare_whiteout(mut dir VFSNode, name string) ?&VFSNode {
 mut upper := dir.overlay.upper
 if overlay_persistent_storage(mut upper.filesystem) {
  return overlay_stage_create(mut dir, stat.ifchr, '', false)
 }
 backing := device_by_name('null')
 if backing == unsafe { nil } { errno.set(errno.eio); return none }
 return prepare_device_node(mut upper, name, stat.ifchr, 0, backing)
}

// Staged inodes have real disk names, but remain outside the merged tree until
// their metadata and final backing rename succeed. Old whiteouts stay named.
fn overlay_staging_work(dir &VFSNode) ?&VFSNode {
 work := dir.overlay.fs.work
 if work == unsafe { nil } || work.removed { errno.set(errno.enoent); return none }
 return overlay_work_child(work, dir.overlay.fs.upper, dir.overlay.fs.staging_owner, true)
}

// A named work directory stays owned by its namespace. On removal, sever all
// raw overlay pointers before normal FD/CWD/grace retirement can reclaim it.
// Do not make it an upper/lower pin: that would retain a deleted disk inode.
fn overlay_detach_work(mut node VFSNode) {
 if node.overlay_work_owners == unsafe { nil } { return }
 overlay_lock.acquire()
 defer { overlay_lock.release() }
 overlay_detach_work_locked(mut node)
}

fn overlay_detach_work_locked(mut node VFSNode) {
 mut owner := node.overlay_work_owners
 node.overlay_work_owners = unsafe { nil }
 for owner != unsafe { nil } {
  next := owner.work_next
  owner.work = unsafe { nil }
  owner.work_next = unsafe { nil }
  owner = next
 }
}

fn overlay_work_child(work &VFSNode, upper &VFSNode, owner u32, private bool) ?&VFSNode {
 child := lookup_child_synced(work, 'work')
 if child == unsafe { nil } || child.removed { errno.set(errno.enoent); return none }
 if child.resource == unsafe { nil } || !stat.isdir(child.resource.stat.mode)
  || child.redir != unsafe { nil } || child.mountpoint != unsafe { nil }
  || child.ns_mounts > 0 || !same_filesystem(child, upper) {
  errno.set(errno.einval); return none
 }
 if private && (child.resource.stat.mode & 0o777 != 0 || child.resource.stat.uid != owner) {
  errno.set(errno.eacces); return none
 }
 return child
}

fn overlay_staging_name(mut ofs OverlayFS, work &VFSNode) ?string {
 for {
  if ofs.staging_serial == ~u64(0) { errno.set(errno.eoverflow); return none }
  ofs.staging_serial++
  mut text := lib.new_text(40)
  text.add('.vinix-stage-')
  text.add_unsigned(ofs.staging_serial)
  name := lib.finish_text(text)
  if name !in work.children { return name }
  unsafe { name.free() }
 }
 return none
}

fn overlay_stage_create(mut dir VFSNode, mode u32, dest string, symlink bool) ?&VFSNode {
 mut work := overlay_staging_work(dir)?
 name := overlay_staging_name(mut dir.overlay.fs, work)?
 defer { unsafe { name.free() } }
 mut real := if symlink {
  overlay_prepare_real_symlink(mut work, dest, name, dir.resource)?
 } else { overlay_prepare_real_create(mut work, name, mode, dir.resource)? }
 // Directory setgid belongs to the final parent, not the private work
 // directory. Generic creation persists the final ACL/mode before commit.
 if stat.isdir(mode) { real.resource.stat.mode = mode & ~u32(0o2000) }
 apply_creation_identity(mut real, dir.overlay.upper) or {
  failure := errno.get()
  discard_created_node(mut real, work)
  errno.set(failure)
  return none
 }
 publish_child(work, name, real)
 return real
}

fn overlay_discard_whiteout(mut node VFSNode) {
 mut parent := node.parent
 mut res := node.resource
 res.unlink(voidptr(node)) or { return }
 if node.name in parent.children && unsafe { voidptr(parent.children[node.name]) == voidptr(node) } {
  remove_child(parent, node.name)
 }
 overlay_release_unlinked_real(mut node)
}

// ── Merging ──────────────────────────────────────────────────────────────────

// An overlay node for `name` in `parent`, showing `real`. `entry` is the heap
// entry it keeps.
fn overlay_node(parent &VFSNode, name string, real &VFSNode, entry &OverlayEntry) &VFSNode {
	is_dir := stat.isdir(real.resource.stat.mode)
	mut node := create_node(parent.filesystem, parent, name, is_dir)
	node.resource = real.resource
	node.read_only = parent.read_only
	if stat.islnk(real.resource.stat.mode) {
		node.symlink_target = real.symlink_target.clone()
	}
	node.overlay = unsafe { entry }
	if !entry.uncommitted { mark_overlaid(entry) }
	return node
}

// A committed entry owns its backing pointers and resources, including after
// unlink while a descriptor, cwd or lockless reader still uses the alias.
fn mark_overlaid(entry &OverlayEntry) {
	mut owned := unsafe { entry }
	if owned.retained { return }
	owned.retained = true
	if entry.upper != unsafe { nil } {
		owned.upper_resource = overlay_retain_node(entry.upper)
	}
	owned.lower_resources = []&resource.Resource{cap: entry.lowers.len} @[freed]
	for lower in entry.lowers {
		owned.lower_resources << overlay_retain_node(lower)
	}
}

fn overlay_retain_node(node &VFSNode) &resource.Resource {
	mut backing := unsafe { node }
	mut res := backing.resource
	resource.retain_resource(mut res)
	katomic.inc(mut &backing.overlay_refs)
	return res
}

// Called by the reaper, after the alias or a removed layer pointer's grace.
// Dropping the last pin starts the backing node's own retirement grace.
fn overlay_release_node(node &VFSNode) {
	mut backing := unsafe { node }
	if !katomic.dec(mut &backing.overlay_refs) && backing.orphan {
		retire_node(mut backing)
	}
}

fn overlay_release_entry(entry &OverlayEntry) {
	if !entry.retained { return }
	if entry.upper != unsafe { nil } {
		overlay_release_node(entry.upper)
		mut res := entry.upper_resource
		resource.release_resource(mut res)
	}
	for index, lower in entry.lowers {
		overlay_release_node(lower)
		mut res := entry.lower_resources[index]
		resource.release_resource(mut res)
	}
}

// bind(2) adopts a socket's namespace reference after generic creation has
// committed its placeholder. Transfer the entry's separate resource pin too.
fn overlay_replace_resource(mut node VFSNode, res &resource.Resource) {
	overlay_lock.acquire()
	defer { overlay_lock.release() }
	mut entry := node.overlay
	if entry.upper != unsafe { nil } {
		mut real := entry.upper
		if entry.retained {
			mut target := unsafe { res }
			resource.retain_resource(mut target)
			replaced := entry.upper_resource
			entry.upper_resource = unsafe { res }
			release_resource_after_grace(replaced)
		}
		real.resource = unsafe { res }
	}
	node.resource = unsafe { res }
}

fn overlay_orphan_alias(mut node VFSNode) {
	mode := node.resource.stat.mode
	if stat.isdir(mode) {
		overlay_detach_work_locked(mut node)
		node.removed = true
	}
	orphan_node(mut node, mode)
}

// Work out a directory's entries from its layers, the first time it is
// looked in.
fn overlay_populate_locked(mut dir VFSNode) {
	mut entry := dir.overlay
	if entry == unsafe { nil } || entry.populated || dir.children == unsafe { nil } {
		return
	}
	entry.populated = true

	mut layers := []&VFSNode{cap: entry.lowers.len + 1} @[freed]
	defer {
		unsafe { layers.free() }
	}
	if entry.upper != unsafe { nil } {
		layers << entry.upper
	}
	if entry.upper == unsafe { nil } || !is_opaque(entry.upper) {
		for lower in entry.lowers {
			layers << lower
		}
	}

	mut merged := map[string]&OverlayMerge{}
	for index, layer in layers {
		// A lower overlay directory can still be lazy. Materialize its merged
		// children before collecting this layer, using the already-held lock.
		mut populated_layer := unsafe { layer }
		overlay_populate_locked(mut populated_layer)
		if layer.children == unsafe { nil } {
			continue
		}
		from_upper := index == 0 && entry.upper != unsafe { nil }
		mut names := layer.children.keys()
		for name in names {
			if is_dot_name(name) {
				continue
			}
			child := unsafe { layer.children[name] }
			if child == unsafe { nil } || child.resource == unsafe { nil } {
				continue
			}
			child_is_dir := stat.isdir(child.resource.stat.mode)
			if name in merged {
				mut item := unsafe { merged[name] }
				if !from_upper && !is_whiteout(child) {
					item.has_lower = true
				}
				if !item.collecting {
					continue
				}
				if !child_is_dir {
					item.collecting = false
					continue
				}
				item.dirs << child
				if is_opaque(child) {
					item.collecting = false
				}
				continue
			}
			mut item := &OverlayMerge{
				top:        child
				from_upper: from_upper
				whiteout:   is_whiteout(child)
				has_lower:  !from_upper && !is_whiteout(child)
				dirs:       []&VFSNode{}
			}
			if child_is_dir {
				item.dirs << child
				item.collecting = !is_opaque(child)
			}
			merged[name] = item
		}
		unsafe { names.free() }
	}

	mut merged_names := merged.keys()
	for name in merged_names {
		mut item := unsafe { merged[name] }
		if !item.whiteout && name !in dir.children {
			mut lowers := []&VFSNode{}
			if stat.isdir(item.top.resource.stat.mode) {
				start := if item.from_upper { 1 } else { 0 }
				for i in start .. item.dirs.len {
					lowers << item.dirs[i]
				}
			} else if !item.from_upper {
				lowers << item.top
			}
			mut child := overlay_node(dir, name.clone(), item.top, &OverlayEntry{
				fs:        entry.fs
				upper:     if item.from_upper { item.top } else { unsafe { nil } }
				lowers:    lowers
				has_lower: item.has_lower
			})
			if stat.isdir(item.top.resource.stat.mode) {
				child.create_dotentries(dir)
			}
			unsafe {
				publish_child(dir, name, child)
			}
		}
		unsafe {
			item.dirs.free()
			free(item)
		}
	}
	unsafe {
		merged_names.free()
		merged.free()
	}
}

// A directory's entries, made ready before a lookup or a listing in it.
pub fn overlay_lookup_refresh(node &VFSNode) {
	if node == unsafe { nil } || node.overlay == unsafe { nil } || node.overlay.populated {
		return
	}
	overlay_lock.acquire()
	defer {
		overlay_lock.release()
	}
	mut dir := unsafe { node }
	overlay_populate_locked(mut dir)
}

// ── Copying up ───────────────────────────────────────────────────────────────

fn overlay_copy_data(mut from resource.Resource, mut to resource.Resource) ? {
	size := u64(from.stat.size)
	if size == 0 {
		return
	}
	to.grow(unsafe { nil }, size)?
	chunk_size := u64(65536)
	mut buffer := unsafe { malloc(chunk_size) }
	defer {
		unsafe { free(buffer) }
	}
	mut offset := u64(0)
	for offset < size {
		wanted := if size - offset < chunk_size { size - offset } else { chunk_size }
		got := from.read(unsafe { nil }, buffer, offset, wanted)?
		if got <= 0 {
			break
		}
		to.write(unsafe { nil }, buffer, offset, u64(got))?
		offset += u64(got)
	}
}

// Give an overlay node its own copy in the upper layer, and its parents
// theirs first.
fn overlay_copy_up_locked(mut node VFSNode) ? {
	mut entry := node.overlay
	if entry == unsafe { nil } || entry.upper != unsafe { nil } {
		return
	}
	// A held lower alias can outlive unlink or replacement. Its old name
	// must never publish another inode or replace a whiteout/new destination.
	if node.orphan || node.removed { errno.set(errno.enoent); return none }
	if entry.fs.upper == unsafe { nil } {
		errno.set(errno.erofs)
		return none
	}
	if entry.lowers.len == 0 || node.parent == unsafe { nil }
		|| node.parent.overlay == unsafe { nil } {
		errno.set(errno.eio)
		return none
	}
	mut parent := node.parent
	overlay_copy_up_locked(mut parent)?
	mut upper_dir := parent.overlay.upper
	lower := entry.lowers[0]
	mut from := lower.resource
	mode := from.stat.mode
	name := node.name

	mut real := &VFSNode(unsafe { nil })
	match mode & stat.ifmt {
		stat.ifdir, stat.ifreg {
			real = overlay_real_create(mut upper_dir, name, mode, from)?
			if stat.isreg(mode) {
				mut to := real.resource
				overlay_copy_data(mut from, mut to) or {
					overlay_drop_real_locked(mut upper_dir, name)
					return none
				}
			}
		}
		stat.iflnk {
			// The upper filesystem keeps a copy of its own.
			real = overlay_real_symlink(mut upper_dir, lower.symlink_target, name, from)?
		}
		stat.ififo {
			real = make_fifo_node(mut upper_dir, name, mode & 0o7777)?
		}
		stat.ifchr, stat.ifblk {
			real = make_device_node(mut upper_dir, name, mode, from.stat.rdev)?
		}
		else {
			errno.set(errno.eperm)
			return none
		}
	}
	mut to := real.resource
	to.stat.mode = mode
	to.stat.uid = from.stat.uid
	to.stat.gid = from.stat.gid
	to.stat.atim = from.stat.atim
	to.stat.mtim = from.stat.mtim
	copy_xattrs(from, to, 'trusted.overlay.') or {
		failure := errno.get()
		overlay_drop_real_locked(mut upper_dir, name)
		errno.set(failure)
		return none
	}
	resource.persist_metadata(mut to) or {
		failure := errno.get()
		overlay_drop_real_locked(mut upper_dir, name)
		errno.set(failure)
		return none
	}
	// Finish data and metadata before installing protections; otherwise the
	// internal copy could be refused. Publish the merged alias only afterwards.
	bits := resource.attributes(mut from) & resource.attributes_kept
	if bits != 0 {
		if !resource.can_have_attributes(mut to) {
			overlay_drop_real_locked(mut upper_dir, name)
			errno.set(errno.enotsup)
			return none
		}
		resource.set_attributes(mut to, bits) or {
			failure := errno.get()
			overlay_drop_real_locked(mut upper_dir, name)
			errno.set(failure)
			return none
		}
	}
	entry.upper = real
	if entry.retained { entry.upper_resource = overlay_retain_node(real) } else { mark_overlaid(entry) }
	node.resource = real.resource
}

pub fn overlay_copy_up(node &VFSNode) ? {
	if node == unsafe { nil } || node.overlay == unsafe { nil } {
		return
	}
	overlay_lock.acquire()
	defer {
		overlay_lock.release()
	}
	mut target := unsafe { node }
	overlay_copy_up_locked(mut target)?
}

// What a change to `node`'s data or attributes is made to: on an overlay the
// upper layer's copy, made first if there is none yet.
fn resource_to_change(node &VFSNode) ?&resource.Resource {
	overlay_copy_up(node)?
	return node.resource
}

// The same for a change made through an open file.
fn handle_resource_to_change(handle_node voidptr, handle_resource &resource.Resource) ?&resource.Resource {
	if handle_node != unsafe { nil } {
		node := unsafe { &VFSNode(handle_node) }
		if node.overlay != unsafe { nil } {
			overlay_copy_up(node)?
			return node.resource
		}
	}
	return handle_resource
}

// ── Changing names ───────────────────────────────────────────────────────────

// Make room for `name` in an overlay directory's upper copy: there may be a
// whiteout there, which the new name replaces. Answers whether there was.
fn overlay_prepare_name_locked(mut dir VFSNode, name string) ?bool {
	overlay_copy_up_locked(mut dir)?
	mut upper_dir := dir.overlay.upper
	if name !in upper_dir.children {
		return false
	}
	existing := unsafe { upper_dir.children[name] }
	if !is_whiteout(existing) {
		errno.set(errno.eexist)
		return none
	}
	return true
}

// The node for a name just made in the upper layer.
fn overlay_new_node(dir &VFSNode, name string, real &VFSNode, replaced_whiteout bool, previous &VFSNode) &VFSNode {
	return overlay_node(dir, name, real, &OverlayEntry{
		fs:        dir.overlay.fs
		// Overlay nodes are heap objects the tree keeps.
		upper:     unsafe { real }
		lowers:    []&VFSNode{}
		has_lower: replaced_whiteout
  rollback_whiteout: unsafe { previous }
  uncommitted: true
		populated: true
	})
}

fn overlay_create_locked(mut dir VFSNode, name string, mode u32) ?&VFSNode {
	mut marker := &XAttrSet(unsafe { nil })
 if stat.isdir(mode) { marker = prepare_opaque_xattr()? }
 defer { if marker != unsafe { nil } { free_xattrs(marker) } }
 replaced_whiteout := overlay_prepare_name_locked(mut dir, name)?
	mut upper_dir := dir.overlay.upper
  mut previous := if replaced_whiteout { unsafe { upper_dir.children[name] } } else { &VFSNode(unsafe { nil }) }
	staged := previous != unsafe { nil } && overlay_persistent_storage(mut upper_dir.filesystem)
	real := if staged { overlay_stage_create(mut dir, mode, '', false)? }
 else { overlay_prepare_real_create(mut upper_dir, name, mode, dir.resource)? }
	mut node := overlay_new_node(dir, name, real, replaced_whiteout, previous)
 node.overlay.staged = staged
	// A directory made where a lower one was removed must not show what that
	// one held.
	if stat.isdir(mode) && replaced_whiteout {
		install_opaque_xattr(real.resource, marker) or {
   failure := errno.get()
   // The factory returns nil, so generic creation still owns this name.
   node.name = ''
   overlay_discard_created_locked(mut dir, mut node)
   errno.set(failure)
   return none
  }
  marker = unsafe { nil }
	}
	// internal_create() adds `.` and `..` to a new directory and links it in.
 return node
}

fn overlay_symlink_locked(mut dir VFSNode, dest string, name string) ?&VFSNode {
	replaced_whiteout := overlay_prepare_name_locked(mut dir, name)?
	mut upper_dir := dir.overlay.upper
  mut previous := if replaced_whiteout { unsafe { upper_dir.children[name] } } else { &VFSNode(unsafe { nil }) }
	staged := previous != unsafe { nil } && overlay_persistent_storage(mut upper_dir.filesystem)
 real := if staged { overlay_stage_create(mut dir, stat.iflnk | 0o777, dest, true)? }
 else { overlay_prepare_real_symlink(mut upper_dir, dest, name, dir.resource)? }
 mut node := overlay_new_node(dir, name, real, replaced_whiteout, previous)
 node.overlay.staged = staged
 return node
}

fn overlay_link_locked(mut dir VFSNode, name string, mut old_node VFSNode) ?&VFSNode {
	if old_node.overlay == unsafe { nil } {
		errno.set(errno.exdev)
		return none
	}
	overlay_copy_up_locked(mut old_node)?
	replaced_whiteout := overlay_prepare_name_locked(mut dir, name)?
	mut upper_dir := dir.overlay.upper
  mut previous := if replaced_whiteout { unsafe { upper_dir.children[name] } } else { &VFSNode(unsafe { nil }) }
	mut old_real := old_node.overlay.upper
	staged := previous != unsafe { nil } && overlay_persistent_storage(mut upper_dir.filesystem)
 mut real_parent := if staged { overlay_staging_work(dir)? } else { upper_dir }
	charge := proc.reserve_kernel(.file, 4096 + u64(name.len) * 2)?
 real_name := if staged { overlay_staging_name(mut dir.overlay.fs, real_parent) or { kbudget.release(charge); return none } } else { name.clone() }
 real := real_parent.filesystem.link(real_parent, real_name, mut old_real) or { unsafe { real_name.free() }; kbudget.release(charge); return none }
 mut charged_real := unsafe { real }; charged_real.kernel_charge = charge
	unsafe {
		publish_child(real_parent, real_name, real)
	}
	mut node := overlay_new_node(dir, name, real, replaced_whiteout, previous)
 node.overlay.staged = staged
 return node
}

// mknod(2) in an overlay directory: a FIFO or a device node in the upper
// layer.
pub fn overlay_mknod(mut dir VFSNode, name string, mode u32, rdev u64) ? {
	overlay_lock.acquire()
	defer {
		overlay_lock.release()
	}
	replaced_whiteout := overlay_prepare_name_locked(mut dir, name)?
	mut upper_dir := dir.overlay.upper
  mut previous := if replaced_whiteout { unsafe { upper_dir.children[name] } } else { &VFSNode(unsafe { nil }) }
	real := if mode & stat.ifmt == stat.ififo {
		make_fifo_node(mut upper_dir, name, mode & 0o7777)?
	} else {
		make_device_node(mut upper_dir, name, mode, rdev)?
	}
	if previous != unsafe { nil } { overlay_dispose_real(mut previous) }
 mut node := overlay_new_node(dir, name.clone(), real, replaced_whiteout, unsafe { nil })
 node.overlay.uncommitted = false
 mark_overlaid(node.overlay)
	unsafe {
		publish_child(dir, name, node)
	}
}

// unlink(2) and rmdir(2) of `node`, `name` in the overlay directory `dir`,
// after the checks every filesystem gets.
fn overlay_unlink(mut dir VFSNode, mut node VFSNode, name string) ? {
	overlay_lock.acquire()
	defer {
		overlay_lock.release()
	}
	is_dir := stat.isdir(node.resource.stat.mode)
	if is_dir {
		overlay_populate_locked(mut node)
		if node.children.len > 2 {
			errno.set(errno.enotempty)
			return none
		}
	}
	overlay_copy_up_locked(mut dir)?
	mut upper_dir := dir.overlay.upper
 mut whiteout := &VFSNode(unsafe { nil })
 if node.overlay.has_lower { whiteout = overlay_prepare_whiteout(mut dir, name)? }
 defer { if whiteout != unsafe { nil } { overlay_discard_whiteout(mut whiteout) } }
	if whiteout != unsafe { nil } && voidptr(whiteout.parent) != voidptr(upper_dir) {
  mut work := whiteout.parent
  final_name := name.clone()
  mut adopted := false
  defer { if !adopted { unsafe { final_name.free() } } }
  work.filesystem.rename(work, whiteout.name, upper_dir, name, 0)?
  mut previous := node.overlay.upper
  children_lock.acquire()
  unsafe {
   if name in upper_dir.children { mut slot := &upper_dir.children[name]; *slot = whiteout }
   else { upper_dir.children[name] = whiteout }
   work.children.delete(whiteout.name)
   dir.children.delete(name)
  }
  children_lock.release()
  adopt(mut whiteout, mut upper_dir, final_name)
  adopted = true
  whiteout = unsafe { nil }
  if previous != unsafe { nil } {
   if is_dir { overlay_drop_whiteouts_locked(mut previous) }
   if previous.resource.stat.nlink > 0 { previous.resource.stat.nlink-- }
   overlay_release_unlinked_real(mut previous)
  }
  overlay_orphan_alias(mut node)
  return
 }
	if node.overlay.upper != unsafe { nil } {
		if is_dir {
			mut real := node.overlay.upper
			overlay_drop_whiteouts_locked(mut real)
		}
		overlay_drop_real_locked(mut upper_dir, name)
	}
	if node.overlay.has_lower {
		publish_child(upper_dir, name, whiteout)
  whiteout = unsafe { nil }
	}
	hold_parent(mut node)
	remove_child(dir, name)
	overlay_orphan_alias(mut node)
}

// rename(2) within one overlay, after the checks every filesystem gets.
fn overlay_rename(mut old_dir VFSNode, old_name string, mut old_node VFSNode, mut new_dir VFSNode, new_name string, new_node &VFSNode) ? {
	overlay_lock.acquire()
	defer {
		overlay_lock.release()
	}
	is_dir := stat.isdir(old_node.resource.stat.mode)
	if is_dir && old_node.overlay.lowers.len > 0 {
		errno.set(errno.exdev)
		return none
	}
	mut replaced := unsafe { new_node }
	if replaced != unsafe { nil } && stat.isdir(replaced.resource.stat.mode) {
		overlay_populate_locked(mut replaced)
		if replaced.children.len > 2 {
			errno.set(errno.enotempty)
			return none
		}
	}
	overlay_copy_up_locked(mut old_node)?
	overlay_copy_up_locked(mut new_dir)?
	mut old_upper := old_dir.overlay.upper
	mut new_upper := new_dir.overlay.upper
	mut real := old_node.overlay.upper
 mut old_whiteout := &VFSNode(unsafe { nil })
 if old_node.overlay.has_lower { old_whiteout = overlay_prepare_whiteout(mut old_dir, old_name)? }
 defer { if old_whiteout != unsafe { nil } { overlay_discard_whiteout(mut old_whiteout) } }

	// What the new name hides below it, which the moved one has to keep
	// hiding.
	mut hides_lower := replaced != unsafe { nil } && replaced.overlay.has_lower
 if replaced == unsafe { nil } && new_name in new_upper.children {
  hides_lower = is_whiteout(unsafe { new_upper.children[new_name] })
 }
 // This directory has no lower layer at its old name; an opacity marker
 // installed here does not alter its contents if the later rename fails.
 if is_dir && hides_lower { xattr_put(real.resource, 'trusted.overlay.opaque', 'y')? }
	mut replaced_real := &VFSNode(unsafe { nil })
	if new_name in new_upper.children { replaced_real = unsafe { new_upper.children[new_name] } }
	replaced_is_dir := replaced != unsafe { nil } && stat.isdir(replaced.resource.stat.mode)
	// Keep both destination slots and their resources until the backend has
	// committed. In particular, a rejected disk name must leave the lower
	// destination visible and an existing upper inode must be replaced by
	// the backend transaction, rather than a separate destructive unlink.
	upper_name := new_name.clone()
	merged_name := new_name.clone()
	whiteout_name := if old_whiteout != unsafe { nil } && voidptr(old_whiteout.parent) != voidptr(old_upper) { old_name.clone() } else { '' }
	mut names_adopted := false
	defer { if !names_adopted { unsafe { upper_name.free(); merged_name.free(); whiteout_name.free() } } }

	overlay_storage_rename(mut old_upper.filesystem, old_upper, old_name, new_upper, new_name, old_whiteout)?
	// Upper and merged paths publish together, with no destination deletion.
	// Readers copy child pointers under this same lock; backend callbacks and
	// retirement remain outside it.
	children_lock.acquire()
	unsafe {
		if replaced_real != nil {
			mut slot := &new_upper.children[new_name]
			*slot = real
		} else { new_upper.children[new_name] = real }
		old_upper.children.delete(old_name)
		if old_whiteout != nil {
   if voidptr(old_whiteout.parent) != voidptr(old_upper) { old_whiteout.parent.children.delete(old_whiteout.name) }
   old_upper.children[old_name] = old_whiteout
  }
		if replaced != nil {
			mut slot := &new_dir.children[new_name]
			*slot = old_node
		} else { new_dir.children[new_name] = old_node }
		old_dir.children.delete(old_name)
	}
	children_lock.release()
	adopt(mut real, mut new_upper, upper_name)
	adopt(mut old_node, mut new_dir, merged_name)
	if old_whiteout != unsafe { nil } && voidptr(old_whiteout.parent) != voidptr(old_upper) {
  adopt(mut old_whiteout, mut old_upper, whiteout_name)
 }
	names_adopted = true
	if old_node.overlay.has_lower {
  old_whiteout = unsafe { nil }
	}
	old_node.overlay.has_lower = hides_lower
	for index, lower in old_node.overlay.lowers {
		overlay_release_after_grace(lower, old_node.overlay.lower_resources[index])
	}
	overlay_retire_lower_arrays(old_node.overlay.lowers, old_node.overlay.lower_resources)
	old_node.overlay.lowers = []&VFSNode{}
	old_node.overlay.lower_resources = []&resource.Resource{}

	if replaced_real != unsafe { nil } {
		if replaced_is_dir { overlay_drop_whiteouts_locked(mut replaced_real) }
		hold_parent(mut replaced_real)
		if replaced_real.resource.stat.nlink > 0 { replaced_real.resource.stat.nlink-- }
		overlay_release_unlinked_real(mut replaced_real)
	}
	if replaced != unsafe { nil } {
		overlay_orphan_alias(mut replaced)
	}
}

// ── Mounting ─────────────────────────────────────────────────────────────────

fn overlay_directory(parent &VFSNode, path string) ?&VFSNode {
	node := get_node(parent, path, true)?
	require_linked(node)?
	if node.resource == unsafe { nil } || !stat.isdir(node.resource.stat.mode) {
		errno.set(errno.enotdir)
		return none
	}
	return node
}

// The root of a new overlay mount, from the options mount(2) was given.
// Relative layer paths are taken from `parent`, the caller's directory:
// Docker gives them so when the absolute ones would not fit in a page.
fn overlay_mount(parent &VFSNode, mount_parent &VFSNode, name string, options string) ?&VFSNode {
	mut lower_spec := ''
	mut upper_path := ''
	mut work_path := ''
	// Docker mounts one of these for every container. split() and the halves
	// of each option were copies nothing freed; the list is freed here and
	// the halves are views into it.
	option_list := options.split(',')
	defer {
		unsafe { option_list.free() }
	}
	for option in option_list {
		if option.len == 0 {
			continue
		}
		equals := option.index_u8(`=`)
		key := if equals < 0 { option } else { unsafe { tos(option.str, equals) } }
		value := if equals < 0 {
			option
		} else {
			unsafe { tos(option.str + equals + 1, option.len - equals - 1) }
		}
		match key {
			'lowerdir' { lower_spec = value }
			'upperdir' { upper_path = value }
			'workdir' { work_path = value }
			// Features this overlay has no use for, or does not have: an index
			// of hard links, redirected and metadata-only copies, inode
			// numbers from more than one filesystem.
			'index', 'redirect_dir', 'metacopy', 'xino', 'nfs_export', 'uuid', 'volatile',
			'userxattr', 'default_permissions' {}
			else {
				errno.set(errno.einval)
				return none
			}
		}
	}
	if lower_spec.len == 0 || (upper_path.len > 0 && work_path.len == 0) {
		errno.set(errno.einval)
		return none
	}
	// new_mount releases this lock before calling the overlay factory. Keep
	// layer resolution and work-owner registration together so rmdir cannot
	// queue a resolved work node before its owner is attached.
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	mut lowers := []&VFSNode{}
	mut layer_depth := 1
	mut layers_assigned := false
 defer { if !layers_assigned { unsafe { lowers.free() } } }
	lower_paths := lower_spec.split(':')
	defer {
		unsafe { lower_paths.free() }
	}
	for path in lower_paths {
		if path.len == 0 {
			errno.set(errno.einval)
			return none
		}
		layer := overlay_directory(parent, path)?
		depth := overlay_layer_depth(layer)
		if depth > overlay_max_layer_depth { errno.set(errno.eloop); return none }
		if depth > layer_depth { layer_depth = depth }
		lowers << layer
	}
	mut upper := &VFSNode(unsafe { nil })
	mut work := &VFSNode(unsafe { nil })
	if upper_path.len > 0 {
		upper = overlay_directory(parent, upper_path)?
		work = overlay_directory(parent, work_path)?
		for layer in [upper, work]! {
			depth := overlay_layer_depth(layer)
			if depth > overlay_max_layer_depth { errno.set(errno.eloop); return none }
			if depth > layer_depth { layer_depth = depth }
		}
		if !same_filesystem(upper, work) { errno.set(errno.exdev); return none }
  if upper.resource.stat.ino == work.resource.stat.ino
   || is_ancestor(upper, work) || is_ancestor(work, upper) { errno.set(errno.einval); return none }
		// Persistent staging stays in a mode-zero directory owned by the
		// mount creator. Validate preexisting directories before trusting them.
		if 'work' !in work.children {
			overlay_real_create(mut work, 'work', stat.ifdir, work.resource)?
		}
  overlay_work_child(work, upper, proc.current_thread().process.euid,
   overlay_persistent_storage(mut upper.filesystem))?
	}
	mut ofs := &OverlayFS{
		dev_id: resource.create_dev_id()
		upper:  upper
		work:   work
		lowers: lowers.clone()
		layer_depth: layer_depth
  staging_owner: proc.current_thread().process.euid
	}
	mut root := create_node(ofs, mount_parent, name, true)
	root.resource = if upper != unsafe { nil } { upper.resource } else { lowers[0].resource }
	root.read_only = upper == unsafe { nil }
	root.overlay = &OverlayEntry{
		fs:     ofs
		upper:  upper
		lowers: lowers
	}
	mark_overlaid(root.overlay)
 if work != unsafe { nil } {
  overlay_lock.acquire()
  ofs.work_next = work.overlay_work_owners
  work.overlay_work_owners = ofs
  overlay_lock.release()
 }
 layers_assigned = true
	return root
}

// Each alias carries its filesystem's maximum accepted backing depth. Layer
// pointers stay fixed for that mount, so admission needs no recursive walk.
fn overlay_layer_depth(node &VFSNode) int {
	return if node.overlay == unsafe { nil } { 1 } else { node.overlay.fs.layer_depth + 1 }
}

// Generic VFS creation performs identity and ACL checks after filesystem.create.
// Reuse its retained whiteout when those checks fail; no fresh quota is needed.
fn overlay_discard_created(mut dir VFSNode, mut node VFSNode) {
 overlay_lock.acquire()
 defer { overlay_lock.release() }
 overlay_discard_created_locked(mut dir, mut node)
}

fn overlay_discard_created_locked(mut dir VFSNode, mut node VFSNode) {
 mut real := node.overlay.upper
 assert node.overlay.uncommitted
 // Generic creation has not published this real or alias in either tree.
 // Their names were kept private through identity/ACL initialization.
 if stat.isdir(real.resource.stat.mode) {
  mut res := real.resource
  // A failed disk unlink may still leave this inode named. Keep its
 // reference and reservation until a safe cleanup is possible.
 res.unlink(voidptr(real)) or { return }
  if node.overlay.staged { remove_child(real.parent, real.name) }
  res.stat.nlink = 0
  real.removed = true
  real.orphan = true
  real.directory_resource = true
  retire_node(mut real)
 } else if node.overlay.staged { overlay_discard_whiteout(mut real) }
 else { overlay_dispose_real(mut real) }
 // The previous whiteout never left its upper slot.
 node.overlay.rollback_whiteout = unsafe { nil }
 if node.children != unsafe { nil } && node.children.len == 0 {
  unsafe { node.children.free(); free(node.children); node.children = nil }
 }
 retire_node(mut node)
}

fn overlay_commit_created(node &VFSNode) ? {
 if node.overlay == unsafe { nil } { return }
 overlay_lock.acquire()
 defer { overlay_lock.release() }
 mut entry := node.overlay
 mut previous := entry.rollback_whiteout
 if entry.staged {
  mut real := entry.upper
  mut work := real.parent
  mut upper := node.parent.overlay.upper
  final_name := node.name.clone()
  mut adopted := false
  defer { if !adopted { unsafe { final_name.free() } } }
  work.filesystem.rename(work, real.name, upper, node.name, 0)?
  children_lock.acquire()
  unsafe {
   mut slot := &upper.children[node.name]
   *slot = real
   work.children.delete(real.name)
  }
  children_lock.release()
  adopt(mut real, mut upper, final_name)
  adopted = true
  entry.staged = false
  entry.uncommitted = false
  if previous != unsafe { nil } {
   if previous.resource.stat.nlink > 0 { previous.resource.stat.nlink-- }
   overlay_release_unlinked_real(mut previous)
   previous = unsafe { nil }
  }
 }
 entry.rollback_whiteout = unsafe { nil }
 if entry.uncommitted {
  mut parent := entry.upper.parent
  publish_child(parent, entry.upper.name, entry.upper)
 }
 entry.uncommitted = false
 mark_overlaid(entry)
 if previous != unsafe { nil } { overlay_dispose_real(mut previous) }
}
