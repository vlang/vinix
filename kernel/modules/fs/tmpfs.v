module fs

struct TmpFS {
	device &VFSNode
}

fn (this TmpFS) populate(node &VFSNode) {}

fn (this TmpFS) mount(node &VFSNode, source string, target string) bool {
	return true
}
