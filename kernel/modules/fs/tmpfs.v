module fs

struct TmpFS {
	device &VFSNode
}

fn (this &TmpFS) populate(node &VFSNode) {}

fn (this &TmpFS) mount(source &VFSNode) &VFSNode {
	return 0
}
