// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import time

// Preserve syscall intent independently of the mutable cached Stat. Remote
// filesystems must not turn a timestamp update into chmod/chown, or send an
// omitted timestamp back to the server from an old attribute snapshot.
pub enum MetadataTime {
	unchanged
	value
	now
}

pub struct MetadataUpdate {
pub:
	mode_set bool
	mode u32
	uid_set bool
	uid u32
	gid_set bool
	gid u32
	// chown clears privilege bits locally; remote ownership operations enforce
	// the same rule themselves. An explicitly supplied mode is applied last.
	clear_setid bool
	atime_kind MetadataTime
	atime time.TimeSpec
	mtime_kind MetadataTime
	mtime time.TimeSpec
	// Local providers use the caller's clock. Remote providers let the server
	// update ctime and interpret .now using the server's clock.
	ctime_set bool
	ctime time.TimeSpec
}

pub interface MetadataUpdateResource {
mut:
	apply_metadata(update &MetadataUpdate) ?
}

struct MetadataUpdateCall {
mut:
	backend MetadataUpdateResource
}

pub fn update_metadata(mut res Resource, update &MetadataUpdate) ? {
	if mut res is MetadataUpdateResource {
		mut call := unsafe { &MetadataUpdateCall(C.vinix_stack_alloc(sizeof(MetadataUpdateCall))) }
		unsafe { call.backend = MetadataUpdateResource(res) }
		call.backend.apply_metadata(update)?
		return
	}
	// Preserve the existing local-provider contract and rollback behavior.
	old := res.stat
	if update.clear_setid { res.stat.mode &= ~u32(0o6000) }
	if update.mode_set { res.stat.mode = update.mode }
	if update.uid_set { res.stat.uid = update.uid }
	if update.gid_set { res.stat.gid = update.gid }
	if update.atime_kind != .unchanged { res.stat.atim = update.atime }
	if update.mtime_kind != .unchanged { res.stat.mtim = update.mtime }
	if update.ctime_set { res.stat.ctim = update.ctime }
	persist_metadata(mut res) or {
		// A provider may refresh other fields during a failed write. Roll back
		// only our staged fields, preserving independently changed metadata.
		if update.mode_set || update.clear_setid { res.stat.mode = old.mode }
		if update.uid_set { res.stat.uid = old.uid }
		if update.gid_set { res.stat.gid = old.gid }
		if update.atime_kind != .unchanged { res.stat.atim = old.atim }
		if update.mtime_kind != .unchanged { res.stat.mtim = old.mtim }
		if update.ctime_set { res.stat.ctim = old.ctim }
		return none
	}
}
