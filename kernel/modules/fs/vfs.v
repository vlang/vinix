module fs

import resource
import stat

interface FileSystem {
	populate(&VFSNode)
	mount(&VFSNode) &VFSNode
	create(&VFSNode, string, int) &VFSNode
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

fn create_node(filesystem &FileSystem) &VFSNode {
	node := &VFSNode{
				mountpoint: 0
				children: map[string]&VFSNode{}
				resource: &resource.Dummy(0)
				filesystem: unsafe { filesystem }
			}
	return node
}

pub fn initialise() {
	vfs_root = create_node(&TmpFS(0))

	filesystems = map[string]FileSystem{}
	fs_instances = []FileSystem{}

	// Install filesystems by name string
	filesystems['tmpfs'] = TmpFS{0, 0}
	filesystems['devtmpfs'] = DevTmpFS{}
}

fn path2node(parent &VFSNode, path string) (&VFSNode, &VFSNode, string) {
	if path.len == 0 {
		return 0, unsafe { parent }, ''
	}

	mut index := u64(0)
	mut current_node := unsafe { parent }

	for path[index] == `/` {
		if index == path.len - 1 {
			return 0, current_node, ''
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
				return current_node, 0, elem_str
			}
			return 0, 0, ''
		}

		new_node := current_node.children[elem_str]

		if last == true {
			return 0, new_node, elem_str
		}

		current_node = new_node

		if !stat.isdir(current_node.resource.stat.mode) {
			return 0, 0, ''
		}
	}

	return 0, 0, ''
}

pub fn get_node(parent &VFSNode, path string) ?&VFSNode {
	_, node, _ := path2node(parent, path)
	if node == 0 {
		return error('File not found')
	}
	return node
}

pub fn mount(parent &VFSNode, source string, target string, filesystem string) bool {
	if filesystem !in filesystems {
		return false
	}

	mut source_node := &VFSNode(0)
	if source.len != 0 {
		_, source_node, _ = path2node(parent, source)
		if source_node == 0
		|| !stat.isreg(source_node.resource.stat.mode) {
			return false
		}
	}

	_, mut target_node, _ := path2node(parent, target)
	if target_node == 0
	|| (target_node != vfs_root && !stat.isdir(target_node.resource.stat.mode))
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

	if source.len > 0 {
		print('vfs: Mounted `${source}` to `${target}` with filesystem `${filesystem}`\n')
	} else {
		print('vfs: Mounted ${filesystem} to `${target}`\n')
	}

	return true
}

pub fn create(parent &VFSNode, name string, mode int) &VFSNode {
	mut parent_of_tgt_node, mut target_node, basename := path2node(parent, name)

	if target_node != 0 {
		return 0
	}

	target_node = parent_of_tgt_node.filesystem.create(parent_of_tgt_node, name, mode)

	parent_of_tgt_node.children[basename] = target_node

	return target_node
}
