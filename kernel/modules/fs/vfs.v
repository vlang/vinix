module fs

import resource
import stat

interface FileSystem {
	device &VFSNode

	populate(&VFSNode)
	mount(&VFSNode) &VFSNode
}

struct VFSNode {
pub mut:
	mountpoint    &VFSNode
	resource      &resource.Resource
	filesystem    &FileSystem
	children      map[string]&VFSNode
}

__global (
	filesystems map[string]FileSystem
	fs_instances []FileSystem
	vfs_root &VFSNode
)

fn new_node(parent &VFSNode, filesystem &FileSystem) &VFSNode {
	node := &VFSNode{
				mountpoint: 0
				children: map[string]&VFSNode{}
				resource: &resource.Dummy(0)
				filesystem: unsafe { filesystem }
			}
	return node
}

pub fn initialise() {
	vfs_root = new_node(&VFSNode(0), &TmpFS(0))

	filesystems = map[string]FileSystem{}
	fs_instances = []FileSystem{}

	// Install filesystems by name string
	filesystems['tmpfs'] = TmpFS{0}
}

fn path2node(parent &VFSNode, path string) (&VFSNode, &VFSNode) {
	if path.len == 0 {
		return 0, unsafe { parent }
	}

	mut index := u64(0)
	mut current_node := unsafe { parent }

	for path[index] == `/` {
		if index == path.len - 1 {
			return 0, current_node
		}
		index++
	}

	for {
		mut elem := []byte{}

		for index < path.len && path[index] != `/` {
			elem << path[index]
			index++
		}

		for index < path.len && path[index] == `/` {
			index++
		}

		last := index == path.len

		elem_str := unsafe { C.byteptr_vstring_with_len(&elem[0], elem.len) }

		for current_node.mountpoint != 0 {
			current_node = current_node.mountpoint
		}

		if elem_str !in current_node.children {
			if last == true {
				return current_node, 0
			}
			return 0, 0
		}

		new_node := current_node.children[elem_str]

		if last == true {
			return 0, new_node
		}

		current_node = new_node

		if !stat.isdir(current_node.resource.stat.mode) {
			return 0, 0
		}
	}

	return 0, 0
}

pub fn mount(parent &VFSNode, source string, target string, filesystem string) bool {
	if filesystem !in filesystems {
		return false
	}

	mut source_node := &VFSNode(0)
	if source.len != 0 {
		_, source_node = path2node(parent, source)
		if source_node == 0
		|| !stat.isreg(source_node.resource.stat.mode) {
			return false
		}
	}

	_, mut target_node := path2node(parent, target)
	if target_node == 0
	|| !stat.isdir(target_node.resource.stat.mode)
	|| target_node.mountpoint != 0 {
		return false
	}

	fs := filesystems[filesystem]

	mount_node := fs.mount(source_node)

	if mount_node == 0 {
		return false
	}

	fs_instances << fs

	target_node.mountpoint = mount_node

	return true
}
