// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The part of /sys other modules fill in.
//
// A device, a driver, a battery or a thermal zone is described where Linux
// describes it -- /sys/bus/pci/devices, /sys/class/power_supply/BAT0,
// /sys/power/state -- so that a program which already reads those files needs
// nothing written for Vinix. The module that owns the thing publishes it with
// the calls below; nothing in here knows what any of the files mean.
//
// An attribute is a file whose text its owner makes when it is read (`show`)
// and, if it can be written, takes when it is written (`store`). Both are
// called with no lock of this file held and may sleep.
//
// Unlike the CPU and node trees, these entries go away again: a card is pulled
// out, a driver is unbound. sysfs_remove() does not return while a show or
// store of a file it removed is still running, so once it has returned the
// owner may free what the file's `context` pointed at. That makes one rule for
// owners: a show or store must not remove its own file, or wait for something
// that does. One that has to -- writing 1 to a device's `remove` -- hands the
// removal to a thread of its own.
//
// Each subtree has one owner, which serializes its own additions and removals;
// two modules do not add to and remove from the same directory at once.
//
// Locking: the tree changes under vfs_lock, as every other filesystem's does,
// and under sysfs_lock, which lookups and listings of /sys take on its own.
module fs

import errno
import katomic
import klock
import lib
import resource
import sched
import stat

// Writes `context`'s text to `text`.
pub type SysfsShow = fn (context voidptr, mut text lib.Text)

// Takes the `length` bytes at `data` -- not NUL terminated, and usually ending
// in the newline echo adds -- for `context`. Returns 0 or an errno.
pub type SysfsStore = fn (context voidptr, data &u8, length u64) u64

// More than any attribute is written with. Linux gives a store one page.
const sysfs_store_limit = u64(4096)

__global (
	sysfs_lock klock.Lock
)

fn is_sysfs_resource(res &resource.Resource) bool {
	return res is SysFSResource && res.stat.dev == sysfs_dev_id && sysfs_dev_id != 0
}

// lookup_child() for a directory of /sys: the map is read under the lock its
// writers hold, and the node copied out of it stays valid for the grace
// period a removed node is kept for.
fn sysfs_lookup_child(node &VFSNode, name string) &VFSNode {
	sysfs_lock.acquire()
	defer {
		sysfs_lock.release()
	}
	if name !in node.children {
		return unsafe { nil }
	}
	child := unsafe { node.children[name] }
	return child
}

// directory_snapshot() for a directory of /sys. As for procfs, the listing
// borrows each node's own name.
fn sysfs_directory_snapshot(node &VFSNode) ([]string, []&VFSNode) {
	sysfs_lock.acquire()
	defer {
		sysfs_lock.release()
	}
	return []string{}, node.children.values()
}

fn (mut this SysFSResource) boxed() &resource.Resource {
	if this.box == unsafe { nil } {
		this.box = &resource.Resource(this) @[freed]
	}
	return this.box
}

// Count a call into the owner in, unless the file has been removed.
fn (mut this SysFSResource) enter() bool {
	katomic.inc(mut &this.busy)
	if katomic.load(&this.gone) != 0 {
		katomic.dec(mut &this.busy)
		return false
	}
	return true
}

fn (mut this SysFSResource) leave() {
	katomic.dec(mut &this.busy)
}

fn (mut this SysFSResource) attribute_text() ?string {
	if !this.enter() {
		errno.set(errno.enodev)
		return none
	}
	// On the stack: a builder made as a local value is moved to the heap when
	// it is handed to the owner, and left there by every read.
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(128) }
	if this.show != unsafe { nil } {
		this.show(this.context, mut text)
	}
	this.leave()
	return text.str()
}

fn (mut this SysFSResource) attribute_store(buf voidptr, count u64) ?i64 {
	if count > sysfs_store_limit {
		errno.set(errno.einval)
		return none
	}
	if !this.enter() {
		errno.set(errno.enodev)
		return none
	}
	code := this.store(this.context, unsafe { &u8(buf) }, count)
	this.leave()
	if code != 0 {
		errno.set(code)
		return none
	}
	return i64(count)
}

// ── Finding the place ───────────────────────────────────────────────────────

// The directory `path` names its last component in, and that component: a view
// into `path`. Directories on the way are made when `create` is set. The
// caller holds both locks.
fn sysfs_parent_of(path string, create bool) (&VFSNode, string) {
	if unsafe { 'sysfs' !in filesystems } {
		return unsafe { nil }, ''
	}
	mut current := sysfs_make_root(unsafe { filesystems['sysfs'] })
	mut start := 0
	for end := 0; end <= path.len; end++ {
		if end < path.len && path[end] != `/` {
			continue
		}
		if end == start {
			start = end + 1
			continue
		}
		component := unsafe { tos(path.str + start, end - start) }
		if end == path.len {
			return current, component
		}
		start = end + 1
		if component in current.children {
			current = unsafe { current.children[component] }
			if current.children == unsafe { nil } {
				return unsafe { nil }, ''
			}
			continue
		}
		if !create {
			return unsafe { nil }, ''
		}
		current = sysfs_new_directory(mut current, component)
	}
	return unsafe { nil }, ''
}

fn sysfs_new_directory(mut parent VFSNode, name string) &VFSNode {
	// Freed with the node, as every name here is: see free_node().
	owned := name.clone()
	mut node := create_node(parent.filesystem, parent, owned, true)
	mut directory := new_sysfs_resource(.directory, stat.ifdir | 0o555, 0)
	directory.dynamic = true
	node.resource = directory.boxed()
	node.create_dotentries(parent)
	unsafe {
		parent.children[owned] = node
		parent.resource.stat.nlink++
	}
	return node
}

fn sysfs_new_leaf(mut parent VFSNode, name string, mut leaf SysFSResource) &VFSNode {
	owned := name.clone()
	mut node := create_node(parent.filesystem, parent, owned, false)
	leaf.dynamic = true
	node.resource = leaf.boxed()
	unsafe {
		parent.children[owned] = node
	}
	return node
}

// ── What owners call ────────────────────────────────────────────────────────

// Make the directory `path`, relative to /sys, and those above it. True if it
// is there afterwards.
pub fn sysfs_directory(path string) bool {
	vfs_lock.acquire()
	sysfs_lock.acquire()
	defer {
		sysfs_lock.release()
		vfs_lock.release()
	}
	mut parent, name := sysfs_parent_of(path, true)
	if parent == unsafe { nil } || name.len == 0 {
		return false
	}
	if name in parent.children {
		existing := unsafe { parent.children[name] }
		return existing.children != unsafe { nil }
	}
	sysfs_new_directory(mut parent, name)
	return true
}

// Publish the file `path`, read through `show` and, when `store` is given,
// written through it. `mode` is its permission bits: 0o444, or 0o644 for one
// root may write. False if the name is taken or the path is not a directory.
pub fn sysfs_attribute(path string, mode u32, show SysfsShow, store SysfsStore, context voidptr) bool {
	vfs_lock.acquire()
	sysfs_lock.acquire()
	defer {
		sysfs_lock.release()
		vfs_lock.release()
	}
	mut parent, name := sysfs_parent_of(path, true)
	if parent == unsafe { nil } || name.len == 0 || name in parent.children {
		return false
	}
	mut attribute := new_sysfs_resource(.attribute, stat.ifreg | (mode & 0o777), 0)
	attribute.show = show
	attribute.store = store
	attribute.context = context
	// What Linux says for every attribute: its text is made when it is read.
	attribute.stat.size = 4096
	sysfs_new_leaf(mut parent, name, mut attribute)
	return true
}

// Publish the file `path` holding `text`, which never changes. The file keeps
// a copy.
pub fn sysfs_text(path string, text string) bool {
	vfs_lock.acquire()
	sysfs_lock.acquire()
	defer {
		sysfs_lock.release()
		vfs_lock.release()
	}
	mut parent, name := sysfs_parent_of(path, true)
	if parent == unsafe { nil } || name.len == 0 || name in parent.children {
		return false
	}
	mut file := new_sysfs_resource(.text, stat.ifreg | 0o444, 0)
	file.text = text.clone()
	file.stat.size = u64(text.len)
	sysfs_new_leaf(mut parent, name, mut file)
	return true
}

// Publish the symbolic link `path` to `target`, which is relative to the
// link's own directory as on Linux: a device's `driver`, a class entry.
pub fn sysfs_link(path string, target string) bool {
	vfs_lock.acquire()
	sysfs_lock.acquire()
	defer {
		sysfs_lock.release()
		vfs_lock.release()
	}
	mut parent, name := sysfs_parent_of(path, true)
	if parent == unsafe { nil } || name.len == 0 || name in parent.children {
		return false
	}
	mut link := new_sysfs_resource(.link, stat.iflnk | 0o777, 0)
	link.stat.size = u64(target.len)
	mut node := sysfs_new_leaf(mut parent, name, mut link)
	node.symlink_target = target.clone()
	return true
}

// Whether `path` is published.
pub fn sysfs_exists(path string) bool {
	vfs_lock.acquire()
	sysfs_lock.acquire()
	defer {
		sysfs_lock.release()
		vfs_lock.release()
	}
	parent, name := sysfs_parent_of(path, false)
	return parent != unsafe { nil } && name.len != 0 && name in parent.children
}

// Remove `path` and, if it is a directory, everything in it. It returns once
// no show or store of a removed file is running; see the top of this file.
// False if there was nothing by that name.
pub fn sysfs_remove(path string) bool {
	vfs_lock.acquire()
	sysfs_lock.acquire()
	mut parent, name := sysfs_parent_of(path, false)
	found := parent != unsafe { nil } && name.len != 0 && name in parent.children
	sysfs_lock.release()
	vfs_lock.release()
	if !found {
		return false
	}
	return sysfs_remove_entry(mut parent, name)
}

// Remove the entry `name` of `parent`, emptying it first if it is a
// directory. One entry is taken out per turn of the loop, with the locks
// dropped between turns: waiting for an attribute's owner to return must not
// be done holding the lock every lookup in /sys needs.
fn sysfs_remove_entry(mut parent VFSNode, name string) bool {
	for {
		vfs_lock.acquire()
		sysfs_lock.acquire()
		if name !in parent.children {
			sysfs_lock.release()
			vfs_lock.release()
			return false
		}
		mut node := unsafe { parent.children[name] }
		if !is_sysfs_resource(node.resource) {
			sysfs_lock.release()
			vfs_lock.release()
			return false
		}
		mut inner := &VFSNode(unsafe { nil })
		if node.children != unsafe { nil } {
			// By the nodes' own names: asking the loop for the map's keys
			// makes it hand out a copy of each, which nothing frees.
			for _, child in node.children {
				if child.name != '.' && child.name != '..' {
					inner = unsafe { child }
					break
				}
			}
		}
		if inner != unsafe { nil } {
			sysfs_lock.release()
			vfs_lock.release()
			// The child's own name: it outlives the locks, as the node does.
			sysfs_remove_entry(mut node, inner.name)
			continue
		}
		mut removed := unsafe { &SysFSResource(node.resource) }
		if !removed.dynamic {
			// Part of the tree made at mount, which nothing takes down.
			sysfs_lock.release()
			vfs_lock.release()
			return false
		}
		katomic.store(mut &removed.gone, u32(1))
		sysfs_detach(mut parent, mut node)
		sysfs_lock.release()
		vfs_lock.release()
		for katomic.load(&removed.busy) != 0 {
			sched.yield(true)
		}
		return true
	}
	return false
}

// Take `node` out of `parent` the way unlink() takes a tmpfs entry out: the
// node waits out the grace period lookups rely on, and a file's resource goes
// when its last descriptor does. Both locks are held.
fn sysfs_detach(mut parent VFSNode, mut node VFSNode) {
	hold_parent(mut node)
	mode := node.resource.stat.mode
	if stat.isdir(mode) {
		node.removed = true
		node.resource.stat.nlink = 0
		node.directory_resource = true
		unsafe {
			if parent.resource.stat.nlink > 2 {
				parent.resource.stat.nlink--
			}
		}
	}
	parent.children.delete(node.name)
	if !node.directory_resource {
		node.resource.stat.nlink = 0
		release_resource_after_grace(node.resource)
	}
	orphan_node(mut node, mode)
}

// ── Reading what was written ────────────────────────────────────────────────

// The text a store was given, without the white space around it: a view into
// `data`, good until the store returns.
pub fn sysfs_word(data &u8, length u64) string {
	mut start := u64(0)
	mut end := length
	for start < end && sysfs_is_space(unsafe { data[start] }) {
		start++
	}
	for end > start && sysfs_is_space(unsafe { data[end - 1] }) {
		end--
	}
	return unsafe { tos(data + start, int(end - start)) }
}

fn sysfs_is_space(c u8) bool {
	return c == ` ` || c == `\t` || c == `\n` || c == `\r` || c == 0
}

// The unsigned decimal number a store was given, or none if it is anything
// else.
pub fn sysfs_unsigned(data &u8, length u64) ?u64 {
	word := sysfs_word(data, length)
	if word.len == 0 || word.len > 20 {
		return none
	}
	mut value := u64(0)
	for i in 0 .. word.len {
		digit := word[i]
		if digit < `0` || digit > `9` {
			return none
		}
		add := u64(digit - `0`)
		if value > (~u64(0) - add) / 10 {
			return none
		}
		value = value * 10 + add
	}
	return value
}
