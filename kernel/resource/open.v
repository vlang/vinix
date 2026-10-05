// SPDX-License-Identifier: GPL-2.0-or-later
module resource

// V promotes a local optional interface on pointer-returning open paths.
// A concrete caller-stack slot keeps dispatch allocation-free; the returned
// device is still owned by the node or by its existing open callback contract.
struct OpenableCall {
mut:
	opener OpenableResource
}

struct OwnedOpenableCall {
mut:
	opener OwnedOpenableResource
}

pub fn open_resource(mut res Resource, flags int) ?OpenedResource {
	if mut res is OwnedOpenableResource {
		mut call := unsafe { &OwnedOpenableCall(C.vinix_stack_alloc(sizeof(OwnedOpenableCall))) }
		unsafe { call.opener = OwnedOpenableResource(res) }
		mut opener := unsafe { &call.opener }
		opened := opener.open_owned(flags) or { return none }
		return OpenedResource{resource: opened, owned: true}
	}
	if mut res is OpenableResource {
		mut call := unsafe { &OpenableCall(C.vinix_stack_alloc(sizeof(OpenableCall))) }
		unsafe { call.opener = OpenableResource(res) }
		mut opener := unsafe { &call.opener }
		opened := opener.open(flags) or { return none }
		return OpenedResource{resource: opened}
	}
	return OpenedResource{resource: unsafe { res }}
}
