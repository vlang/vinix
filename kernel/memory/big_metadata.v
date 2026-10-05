// SPDX-License-Identifier: GPL-2.0-or-later
module memory

const malloc_metadata_magic = u64(0x56494e4958424947)
const malloc_metadata_salt = u64(0x9e3779b97f4a7c15)

// page_size is a boot-selected global on amd64. A derived V const would be
// initialized by _vinit after the early heap self-test has already used it.
@[inline]
fn big_allocation_max_size() u64 {
	return (u64(-1) / page_size - 1) * page_size
}

struct MallocMetadata {
mut:
	magic u64
	pages u64
	size u64
	pages_inv u64
	size_inv u64
	cookie u64
}

// An integrity tripwire, not a secret MAC. Bind the header to its own address
// as well as its geometry; a coherent attacker rewrite is outside its scope.
fn malloc_metadata_cookie(address u64, pages u64, size u64) u64 {
	return malloc_metadata_magic ^ malloc_metadata_salt ^ address ^ (pages << 17) ^ size
}

fn big_metadata_valid(metadata &MallocMetadata) bool {
	if metadata.magic != malloc_metadata_magic || metadata.pages == 0
		|| metadata.size == 0 || metadata.size > big_allocation_max_size()
		|| metadata.pages_inv != ~metadata.pages || metadata.size_inv != ~metadata.size {
		return false
	}
	// The ceiling must not overflow even for a corrupt, internally consistent
	// size. Validate its bound before adding page_size - 1.
	return (metadata.size + page_size - 1) / page_size == metadata.pages
		&& metadata.cookie == malloc_metadata_cookie(u64(metadata), metadata.pages, metadata.size)
}

fn update_big_metadata(mut metadata MallocMetadata, pages u64, size u64) {
	metadata.magic = malloc_metadata_magic
	metadata.pages = pages
	metadata.size = size
	metadata.pages_inv = ~pages
	metadata.size_inv = ~size
	metadata.cookie = malloc_metadata_cookie(u64(metadata), pages, size)
}

fn invalidate_big_metadata(mut metadata MallocMetadata) {
	metadata.magic = 0
	metadata.pages = 0
	metadata.size = 0
	metadata.pages_inv = 0
	metadata.size_inv = 0
	metadata.cookie = 0
}
