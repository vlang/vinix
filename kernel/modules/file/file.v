module file

import resource
import fs

pub struct Handle {
pub mut:
	is_directory bool
	resource &resource.Resource
	node &fs.VFSNode
	refcount int
	loc u64
	flags int
}

pub struct FD {
pub mut:
	handle &Handle
	flags int
}
