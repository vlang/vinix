// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What a hibernation image is on its device, and what makes one valid.
//
// The device is the image's alone and is written from its first byte:
//
//	block 0       the header, below; the rest of the block is zero
//	block 1 ...   the number of the page frame each saved page came from,
//	              eight bytes each, in ascending order
//	then          the pages themselves, 4096 bytes each, in that order
//
// A block is 4096 bytes. Everything is in the byte order of the machine that
// wrote it, which is the only machine that may read it.
//
// The header is written last, after the pages have been written and flushed,
// and is what makes them an image: a device whose first block is not a
// header with the right signature, version and checksum, describing pages
// that lie within the device, holds no image. Before anything else is
// written, and before a loaded image is entered, the block is replaced with
// a header that describes no pages. That one says the device is this
// system's to write to, and nothing more.
//
// The checksums are there to tell a whole image from a torn or decayed one.
// They are not a signature: whoever can write the device can write an image
// the kernel will enter, as they could write the kernel itself.
//
// Nothing here touches a device or the machine, so that it can be tried on
// the host (tests/hibernate).
module hibernate

pub const block_bytes = u64(4096)
// "VINIXHIB", first byte lowest.
pub const image_magic = u64(0x4249485849_4e4956)
pub const format_version = u64(1)

// What the machine was when the image was taken. A kernel is entered again
// only on a machine that answers the same to every one of these: the image
// holds pointers into the boot loader's and firmware's tables, the kernel's
// own page tables, and a processor's saved registers.
pub struct Machine {
pub mut:
	// Where the kernel is mapped and where it lies in memory, how long it
	// is, and a digest of its code and constants.
	kernel_virtual  u64
	kernel_physical u64
	kernel_bytes    u64
	kernel_digest   u64
	// The offset of the direct map, and the depth of the page tables.
	direct_map    u64
	paging_levels u64
	// The boot loader's memory map, as two digests. One is of the memory
	// the kernel has, as the runs of addresses it comes to: usable, the boot
	// loader's own and the kernel's together, since where the boot loader
	// draws the lines between those three moves from one boot to the next
	// and an image does not depend on it. The other is of every entry that
	// is not such memory -- firmware's regions, ACPI's, the framebuffer --
	// each by where it is, how long and what kind.
	map_memory u64
	map_fixed  u64
	// One past the last byte of memory the kernel has.
	memory_top u64
	// ACPI: where the root pointer is, and a digest of every table's address
	// and contents.
	acpi_root   u64
	acpi_tables u64
	// The framebuffer's address, and a digest of its geometry.
	framebuffer        u64
	framebuffer_layout u64
	// How many processors, and a digest of their APIC numbers and features.
	processors       u64
	processor_digest u64
	// The kernel command line.
	command_line u64
	// The pages under 1 MiB processors are started on.
	low_base  u64
	low_pages u64
}

pub struct Header {
pub mut:
	magic   u64
	version u64
	// Of this structure with this field zero.
	checksum u64
	// How many pages; 0 for a device that is claimed and holds no image.
	pages u64
	// Where the frame numbers, the pages and the end of the image are, in
	// bytes from the start of the device.
	list_offset u64
	data_offset u64
	end_offset  u64
	// Of the frame numbers, and of the pages in order.
	list_checksum u64
	data_checksum u64
	// How to enter the image: an address in the kernel to jump to, with the
	// address of the saved processor as its argument, once every page is in
	// its frame.
	entry   u64
	context u64
	// The frame of a page of the image the loader fills in before it enters:
	// see Handover.
	handover u64
	// When it was taken, in seconds by the battery-backed clock, and how
	// many images this kernel had written before it.
	taken_at u64
	sequence u64
	// How long copying the pages took, with the machine stopped, and how
	// long writing them to the device took, in nanoseconds: for the kernel
	// inside the image, which was not there to see.
	copy_time  u64
	write_time u64
	machine    Machine
}

// What the kernel that loaded the image tells the one inside it. It is
// written into the image's own page for it, after the page has been read
// from the device.
pub struct Handover {
pub mut:
	magic u64
	// How long the loading kernel had been running when it entered the
	// image, and how long reading the image took, in nanoseconds.
	loader_uptime u64
	load_time     u64
	// Pages read straight into their frames, and pages that had to be put
	// elsewhere first because the loading kernel was using theirs.
	direct    u64
	relocated u64
	// Writes block drivers had been asked for in the loading kernel before
	// it looked for an image. An image is only entered when this is zero.
	writes_before u64
	// From the image's header: see there.
	copy_time  u64
	write_time u64
	// The bytes of the image on the device.
	image_bytes u64
}

pub const handover_magic = u64(0x5245564f444e4148)

// One step of the checksum: `value` folded into `sum`.
@[inline]
pub fn mix(sum u64, value u64) u64 {
	mut x := (sum ^ value) * u64(0x9e3779b97f4a7c15)
	x ^= x >> 29
	x *= u64(0xbf58476d1ce4e5b9)
	x ^= x >> 32
	return x
}

pub fn sum_words(seed u64, words &u64, count u64) u64 {
	mut sum := seed
	for i in u64(0) .. count {
		sum = mix(sum, unsafe { words[i] })
	}
	return sum
}

// The same over bytes: whole words first, then what is left, one at a time.
pub fn sum_bytes(seed u64, bytes &u8, count u64) u64 {
	mut sum := sum_words(seed, unsafe { &u64(bytes) }, count / 8)
	for i in (count / 8) * 8 .. count {
		sum = mix(sum, u64(unsafe { bytes[i] }))
	}
	return mix(sum, count)
}

pub fn header_checksum(header &Header) u64 {
	mut unsealed := *header
	unsealed.checksum = 0
	// Not in the return itself: a pointer to a local there has the compiler
	// move the local to the heap, for good.
	words := unsafe { &u64(voidptr(&unsealed)) }
	sum := sum_words(image_magic, words, sizeof(Header) / 8)
	return sum
}

// How many bytes the frame numbers of `pages` pages take on the device.
pub fn list_bytes(pages u64) u64 {
	return (pages * 8 + block_bytes - 1) / block_bytes * block_bytes
}

// How many bytes an image of `pages` pages takes.
pub fn image_bytes(pages u64) u64 {
	return block_bytes + list_bytes(pages) + pages * block_bytes
}

// A header for `pages` pages with the offsets they imply; the checksums of
// the contents, the way in and the machine are the caller's to fill in, and
// seal() comes last.
pub fn new_header(pages u64, sequence u64) Header {
	mut header := Header{
		magic:    image_magic
		version:  format_version
		pages:    pages
		sequence: sequence
	}
	if pages != 0 {
		header.list_offset = block_bytes
		header.data_offset = block_bytes + list_bytes(pages)
		header.end_offset = image_bytes(pages)
	}
	return header
}

pub fn seal(mut header Header) {
	header.checksum = header_checksum(header)
}

pub enum Verdict {
	// Not a header of this system's at all: the device is somebody else's,
	// or blank.
	foreign
	// A header that describes no pages: the device is claimed, with no image.
	empty
	// A header that says it describes an image and cannot be believed.
	damaged
	// A whole header for an image that fits the device.
	image
}

// What the first block of a device of `device_bytes` bytes is. `why` says
// what is wrong with a damaged one.
pub fn judge_header(header &Header, device_bytes u64) (Verdict, string) {
	if header.magic != image_magic {
		return Verdict.foreign, ''
	}
	if header.version != format_version {
		return Verdict.damaged, 'it was written in a format this kernel does not read'
	}
	if header.checksum != header_checksum(header) {
		return Verdict.damaged, 'its header does not match its checksum'
	}
	if header.pages == 0 {
		return Verdict.empty, ''
	}
	// Each of these follows from the number of pages; a header that says
	// otherwise was not written by new_header().
	if header.pages > device_bytes / block_bytes || header.list_offset != block_bytes
		|| header.data_offset != block_bytes + list_bytes(header.pages)
		|| header.end_offset != image_bytes(header.pages) {
		return Verdict.damaged, 'its header describes an image that cannot be'
	}
	if header.end_offset > device_bytes {
		return Verdict.damaged, 'it is longer than the device'
	}
	if header.entry == 0 || header.context == 0 || header.handover == 0 {
		return Verdict.damaged, 'its header does not say how to enter it'
	}
	return Verdict.image, ''
}

// Why a kernel on the machine `here` may not enter an image taken on the
// machine `image`, or '' when it may. The first difference found is the one
// named; the order is from what is most likely to have been changed on
// purpose to what should never differ.
pub fn machine_difference(image &Machine, here &Machine) string {
	if image.kernel_bytes != here.kernel_bytes || image.kernel_digest != here.kernel_digest {
		return 'it was taken by another kernel'
	}
	if image.command_line != here.command_line {
		return 'the kernel command line has changed'
	}
	if image.map_memory != here.map_memory || image.memory_top != here.memory_top {
		return 'the memory of the machine has changed'
	}
	if image.map_fixed != here.map_fixed {
		return 'the regions of memory firmware keeps have changed'
	}
	// Where in memory the boot loader put the kernel is not compared: it
	// moves by a few pages from one boot of the same machine to the next,
	// and the image is entered through a page table that maps the kernel's
	// addresses to where the image's kernel is.
	if image.kernel_virtual != here.kernel_virtual {
		return 'the kernel is mapped somewhere else'
	}
	if image.direct_map != here.direct_map || image.paging_levels != here.paging_levels {
		return 'the address space is laid out differently'
	}
	if image.processors != here.processors || image.processor_digest != here.processor_digest {
		return 'the processors have changed'
	}
	if image.acpi_root != here.acpi_root || image.acpi_tables != here.acpi_tables {
		return 'the ACPI tables have changed'
	}
	if image.framebuffer != here.framebuffer || image.framebuffer_layout != here.framebuffer_layout {
		return 'the display is set up differently'
	}
	if image.low_base != here.low_base || image.low_pages != here.low_pages {
		return 'the pages processors start on have moved'
	}
	return ''
}
