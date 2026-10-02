// SPDX-License-Identifier: GPL-2.0-or-later
module resource

// Narrowing an interface for a mut method otherwise boxes a temporary that
// V never frees. This wrapper borrows only the dispatch value on our stack.
struct OpenScratch { mut: backend OpenableResource }

pub fn open_resource(mut res Resource, flags int) ?&Resource {
	if mut res is OpenableResource {
		mut stack := unsafe { &OpenScratch(C.__builtin_alloca(sizeof(OpenScratch))) }
		unsafe { stack.backend = OpenableResource(res) }
		// The implementation returns its own Resource box, never this scratch.
		return stack.backend.open(flags)
	}
	return unsafe { res }
}
