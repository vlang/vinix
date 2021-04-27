module fs

import resource

enum FileType {
	regular_file
	hard_link
	sym_link
	char_dev
	block_dev
	directory
	fifo
}

interface FileSystem {
	device &VFSNode

	populate(&VFSNode)
	mount(&VFSNode, string, string) bool
}

struct VFSNode {
pub mut:
	available  bool
	filetype   FileType
	children   map[string]VFSNode
	resource   &resource.Resource
	filesystem &FileSystem
}

__global (
	filesystems map[string]FileSystem
)

__global (
	vfs_root VFSNode
)

pub fn vfs_init() {
	filesystems = map[string]FileSystem{}

	// Install filesystems by name string
	filesystems['tmpfs'] = TmpFS{0}
}

enum Path2NodeFlags {
	no_create      = 0b0000
	create_shallow = 0b0001
	create_deep    = 0b0010
	no_deref_links = 0b0100
	fail_if_exists = 0b1000
}

fn path2node(parent &VFSNode, path string, flags Path2NodeFlags) &VFSNode {
	if path.len == 0 {
		return 0
	}

	mut index := u64(0)
	mut current_node := parent

	for {
		for path[index] == `/` {
			if index == path.len - 1 {
				return current_node
			}
			index++
		}

		mut elem := []byte{}

		for index < path.len && path[index] != `/` {
			elem << path[index]
			index++
		}

		last := if index == path.len { true } else { false }

		elem_str := unsafe { C.byteptr_vstring_with_len(&elem[0], elem.len) }

		if elem_str !in current_node.children {
			if last == true {
				// create_shallow stuff goes here, fail for now
				return 0
			} else {
				// create_deep stuff goes here, fail for now
				return 0
			}
		}

		current_node = &(current_node.children[elem_str])

		if last == true {
			return current_node
		}

		if current_node.filetype != .directory {
			return 0
		}
	}

	return 0
}

pub fn mount(parent &VFSNode, source string, target string, filesystem string) bool {
	if filesystem !in filesystems {
		return false
	}

	fs := filesystems[filesystem]

	return fs.mount(parent, source, target)
}
