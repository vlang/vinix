@[has_globals]
module fs

import resource
import klock

#flag -Dvinix_stack_alloc=__builtin_alloca

fn C.vinix_stack_alloc(usize) voidptr

pub interface FileSystem {
mut:
	instantiate() &FileSystem
	populate(&VFSNode)
	mount(&VFSNode, string, &VFSNode) ?&VFSNode
	create(&VFSNode, string, u32) &VFSNode
	symlink(&VFSNode, string, string) &VFSNode
	link(&VFSNode, string, mut VFSNode) ?&VFSNode
	rename(&VFSNode, string, &VFSNode, string, int) ?
}

pub struct VFSNode {
pub mut:
	filesystem         &FileSystem          = unsafe { nil }
	resource           &resource.Resource   = unsafe { nil }
	parent             &VFSNode             = unsafe { nil }
	children           &map[string]&VFSNode = unsafe { nil }
	name               string
	redir              &VFSNode = unsafe { nil }
	removed            bool
	orphan             bool
	directory_resource bool
	handles            int
	overlay_refs       int
}

pub struct Mount {
pub mut:
	root           &VFSNode = unsafe { nil }
	detached       bool
	unmount_closed bool
}

pub struct MountTable {
pub mut:
	lock   klock.Lock
	mounts []&Mount
}

__global initial_mount_table &MountTable
__global nsfs_dev_id u64

pub fn create_node(filesystem &FileSystem, parent &VFSNode, name string, dir bool) &VFSNode {
	mut node := &VFSNode{ filesystem: filesystem, parent: unsafe { parent }, name: name }
	if dir { node.children = &map[string]&VFSNode{} }
	return node
}

pub fn (mut node VFSNode) create_dotentries(parent &VFSNode) {
	mut dot := create_node(node.filesystem, node, '.', false)
	dot.redir = node
	mut dotdot := create_node(node.filesystem, node, '..', false)
	dotdot.redir = parent
	publish_child(node, '.', dot)
	publish_child(node, '..', dotdot)
}

pub fn publish_child(parent &VFSNode, name string, child &VFSNode) {
	mut dir := unsafe { parent }
	unsafe { dir.children[name] = child }
}

fn remove_child(parent &VFSNode, name string) {
	mut dir := unsafe { parent }
	dir.children.delete(name)
}

fn lookup_child_synced(node &VFSNode, name string) &VFSNode {
	return unsafe { node.children[name] or { nil } }
}

fn hold_parent(mut _ VFSNode) {}

fn orphan_node(mut node VFSNode, _ u32) { node.orphan = true }

fn release_resource_after_grace(_ &resource.Resource) {}
