module resource

// Optional capabilities keep stream/device resources and in-memory files from
// needing dummy callbacks merely because disk-backed resources cache writes.
pub interface SyncableResource {
mut:
	sync(handle voidptr) ?
}

pub interface AdvisableResource {
mut:
	advise(handle voidptr, offset u64, length u64, advice int) ?
}

pub fn sync_resource(mut res Resource, handle voidptr) ? {
	if mut res is SyncableResource {
		res.sync(handle) or { return none }
	}
}

pub fn advise_resource(mut res Resource, handle voidptr, offset u64, length u64, advice int) ? {
	if mut res is AdvisableResource {
		res.advise(handle, offset, length, advice) or { return none }
	}
}
