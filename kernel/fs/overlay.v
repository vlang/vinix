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
import klock
import proc
import resource
import stat

struct OverlayFS {
mut:
	dev_id u64
	upper  &VFSNode = unsafe { nil }
	work   &VFSNode = unsafe { nil }
	lowers []&VFSNode
}

// What an overlay node is made of.
pub struct OverlayEntry {
mut:
	fs &OverlayFS = unsafe { nil }
	// The name in the upper layer, once there is one.
	upper &VFSNode = unsafe { nil }
	// A directory's lower directories, highest first, down to the first
	// opaque one; for anything else, the lower file it shows while it has no
	// upper copy.
	lowers []&VFSNode
	// Some lower layer has this name, so removing it takes a whiteout.
	has_lower bool
	// A directory's merged entries have been worked out.
	populated bool
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

fn is_whiteout(node &VFSNode) bool {
	return node != unsafe { nil } && node.resource != unsafe { nil }
		&& node.resource.stat.mode & stat.ifmt == stat.ifchr && node.resource.stat.rdev == 0
}

fn is_opaque(node &VFSNode) bool {
	if node == unsafe { nil } || node.resource == unsafe { nil }
		|| !stat.isdir(node.resource.stat.mode) {
		return false
	}
	return xattr_equals(node.resource, 'trusted.overlay.opaque', 'y')
}

// A name in a real directory, made as the kernel makes it, without the
// caller's permission checks: a copy up is done for the caller, whoever it is.
fn overlay_real_create(mut dir VFSNode, name string, mode u32) ?&VFSNode {
	mut real := dir.filesystem.create(dir, name, mode)
	if real == unsafe { nil } {
		if errno.get() == 0 {
			errno.set(errno.eio)
		}
		return none
	}
	unsafe {
		dir.children[name] = real
	}
	if stat.isdir(mode) {
		real.create_dotentries(dir)
	}
	return real
}

fn overlay_real_symlink(mut dir VFSNode, dest string, name string) ?&VFSNode {
	mut real := dir.filesystem.symlink(dir, dest, name)
	if real == unsafe { nil } {
		if errno.get() == 0 {
			errno.set(errno.eio)
		}
		return none
	}
	unsafe {
		dir.children[name] = real
	}
	return real
}

// Take `name` out of a real directory. A directory is left with its entries
// map, which only whiteouts can still be in, and its resource too while
// `held`: something stands in the overlay directory that leads to it.
fn overlay_drop_real_locked(mut dir VFSNode, name string, held bool) {
	if name !in dir.children {
		return
	}
	mut real := unsafe { dir.children[name] }
	dir.children.delete(name)
	if real == unsafe { nil } || real.resource == unsafe { nil } {
		return
	}
	mut res := real.resource
	res.unlink(voidptr(real)) or {}
	if stat.isdir(res.stat.mode) {
		real.removed = true
		res.stat.nlink = 0
	}
	if !held {
		res.unref(unsafe { nil }) or {}
	}
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
			overlay_drop_real_locked(mut dir, name, false)
		}
	}
}

fn overlay_whiteout_locked(mut dir VFSNode, name string) ? {
	backing := device_by_name('null')
	if backing == unsafe { nil } {
		errno.set(errno.eio)
		return none
	}
	install_device_node(mut dir, name.clone(), stat.ifchr, 0, backing)?
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
	return node
}

// Work out a directory's entries from its layers, the first time it is
// looked in.
fn overlay_populate_locked(mut dir VFSNode) {
	mut entry := dir.overlay
	if entry == unsafe { nil } || entry.populated || dir.children == unsafe { nil } {
		return
	}
	entry.populated = true

	mut layers := []&VFSNode{cap: entry.lowers.len + 1}
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
				dir.children[name] = child
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
			real = overlay_real_create(mut upper_dir, name, mode)?
			if stat.isreg(mode) {
				mut to := real.resource
				overlay_copy_data(mut from, mut to) or {
					overlay_drop_real_locked(mut upper_dir, name, false)
					return none
				}
			}
		}
		stat.iflnk {
			real = overlay_real_symlink(mut upper_dir, lower.symlink_target.clone(), name)?
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
	copy_xattrs(from, to, 'trusted.overlay.')
	entry.upper = real
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
	overlay_drop_real_locked(mut upper_dir, name, false)
	return true
}

// The node for a name just made in the upper layer.
fn overlay_new_node(dir &VFSNode, name string, real &VFSNode, replaced_whiteout bool) &VFSNode {
	return overlay_node(dir, name, real, &OverlayEntry{
		fs:        dir.overlay.fs
		upper:     real
		lowers:    []&VFSNode{}
		has_lower: replaced_whiteout
		populated: true
	})
}

fn overlay_create_locked(mut dir VFSNode, name string, mode u32) ?&VFSNode {
	replaced_whiteout := overlay_prepare_name_locked(mut dir, name)?
	mut upper_dir := dir.overlay.upper
	real := overlay_real_create(mut upper_dir, name, mode)?
	// A directory made where a lower one was removed must not show what that
	// one held.
	if stat.isdir(mode) && replaced_whiteout {
		xattr_put(real.resource, 'trusted.overlay.opaque', 'y')
	}
	// internal_create() adds `.` and `..` to a new directory and links it in.
	return overlay_new_node(dir, name, real, replaced_whiteout)
}

fn overlay_symlink_locked(mut dir VFSNode, dest string, name string) ?&VFSNode {
	replaced_whiteout := overlay_prepare_name_locked(mut dir, name)?
	mut upper_dir := dir.overlay.upper
	real := overlay_real_symlink(mut upper_dir, dest, name)?
	return overlay_new_node(dir, name, real, replaced_whiteout)
}

fn overlay_link_locked(mut dir VFSNode, name string, mut old_node VFSNode) ?&VFSNode {
	if old_node.overlay == unsafe { nil } {
		errno.set(errno.exdev)
		return none
	}
	overlay_copy_up_locked(mut old_node)?
	replaced_whiteout := overlay_prepare_name_locked(mut dir, name)?
	mut upper_dir := dir.overlay.upper
	mut old_real := old_node.overlay.upper
	real := upper_dir.filesystem.link(upper_dir, name, mut old_real)?
	unsafe {
		upper_dir.children[name] = real
	}
	return overlay_new_node(dir, name, real, replaced_whiteout)
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
	real := if mode & stat.ifmt == stat.ififo {
		make_fifo_node(mut upper_dir, name, mode & 0o7777)?
	} else {
		make_device_node(mut upper_dir, name, mode, rdev)?
	}
	node := overlay_new_node(dir, name, real, replaced_whiteout)
	unsafe {
		dir.children[name] = node
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
	held := is_dir && proc.directory_in_use(voidptr(node))
	if node.overlay.upper != unsafe { nil } {
		if is_dir {
			mut real := node.overlay.upper
			overlay_drop_whiteouts_locked(mut real)
		}
		overlay_drop_real_locked(mut upper_dir, name, held)
	}
	if node.overlay.has_lower {
		overlay_whiteout_locked(mut upper_dir, name)?
	}
	dir.children.delete(name)
	if is_dir {
		node.removed = true
	}
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

	// What the new name hides below it, which the moved one has to keep
	// hiding.
	mut hides_lower := false
	if replaced != unsafe { nil } {
		hides_lower = replaced.overlay.has_lower
		replaced_is_dir := stat.isdir(replaced.resource.stat.mode)
		held := replaced_is_dir && proc.directory_in_use(voidptr(replaced))
		if replaced.overlay.upper != unsafe { nil } {
			if replaced_is_dir {
				mut replaced_real := replaced.overlay.upper
				overlay_drop_whiteouts_locked(mut replaced_real)
			}
			overlay_drop_real_locked(mut new_upper, new_name, held)
		}
		new_dir.children.delete(new_name)
		if replaced_is_dir {
			replaced.removed = true
		}
	} else if new_name in new_upper.children {
		if is_whiteout(unsafe { new_upper.children[new_name] }) {
			overlay_drop_real_locked(mut new_upper, new_name, false)
			hides_lower = true
		}
	}

	old_upper.filesystem.rename(old_upper, old_name, new_upper, new_name, 0)?
	old_upper.children.delete(old_name)
	unsafe {
		new_upper.children[new_name] = real
	}
	adopt(mut real, mut new_upper, new_name)
	if is_dir && hides_lower {
		xattr_put(real.resource, 'trusted.overlay.opaque', 'y')
	}
	if old_node.overlay.has_lower {
		overlay_whiteout_locked(mut old_upper, old_name)?
	}
	old_node.overlay.has_lower = hides_lower
	unsafe { old_node.overlay.lowers.free() }
	old_node.overlay.lowers = []&VFSNode{}

	old_dir.children.delete(old_name)
	unsafe {
		new_dir.children[new_name] = old_node
	}
	adopt(mut old_node, mut new_dir, new_name)
}

// ── Mounting ─────────────────────────────────────────────────────────────────

fn overlay_directory(parent &VFSNode, path string) ?&VFSNode {
	node := get_node(parent, path, true)?
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
	for option in options.split(',') {
		if option.len == 0 {
			continue
		}
		key := option.all_before('=')
		value := option.all_after('=')
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
	mut lowers := []&VFSNode{}
	for path in lower_spec.split(':') {
		if path.len == 0 {
			errno.set(errno.einval)
			return none
		}
		lowers << overlay_directory(parent, path)?
	}
	mut upper := &VFSNode(unsafe { nil })
	mut work := &VFSNode(unsafe { nil })
	if upper_path.len > 0 {
		upper = overlay_directory(parent, upper_path)?
		work = overlay_directory(parent, work_path)?
		// Linux keeps its own directory in the work directory, and Docker
		// chowns it right after mounting.
		if 'work' !in work.children {
			overlay_real_create(mut work, 'work', stat.ifdir)?
		}
	}
	mut ofs := &OverlayFS{
		dev_id: resource.create_dev_id()
		upper:  upper
		work:   work
		lowers: lowers.clone()
	}
	mut root := create_node(ofs, mount_parent, name, true)
	root.resource = if upper != unsafe { nil } { upper.resource } else { lowers[0].resource }
	root.read_only = upper == unsafe { nil }
	root.overlay = &OverlayEntry{
		fs:     ofs
		upper:  upper
		lowers: lowers
	}
	return root
}
