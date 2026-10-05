module mmap

import memory

fn test_final_mappings_skip_writable_overlaps_and_holes() {
	mut first := memory.Range{base: 0x1000, length: 0x1000, prot: 5}
	mut replaced := memory.Range{base: 0x2000, length: 0x1000, prot: 3}
	mut last := memory.Range{base: 0x4000, length: 0x1000, prot: 5}
	mut pagemap := memory.Pagemap{ranges: [unsafe { &first }, unsafe { &replaced }, unsafe { &last }]}
	mimmutable_executable(mut pagemap, 0x1000, 0x4000)
	assert first.immutable && last.immutable
	assert !replaced.immutable
	assert !pagemap.l.held
	mimmutable_executable(mut pagemap, 0x1000, 0x4000)
	assert first.immutable && last.immutable
}

fn test_loader_filter_requires_whole_executable_nonwritable_range() {
	mut partial := memory.Range{base: 0x1000, length: 0x2000, prot: 5}
	mut ro := memory.Range{base: 0x4000, length: 0x1000, prot: 1}
	mut rwx := memory.Range{base: 0x5000, length: 0x1000, prot: 7}
	mut pagemap := memory.Pagemap{ranges: [unsafe { &partial }, unsafe { &ro }, unsafe { &rwx }]}
	mimmutable_executable(mut pagemap, 0x1000, 0x1000)
	mimmutable_executable(mut pagemap, 0x4000, 0x2000)
	assert !partial.immutable && !ro.immutable && !rwx.immutable
}
