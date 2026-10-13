// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Taking an image of memory, and writing it to its device.
//
// Which pages are saved is read off the allocator and the boot loader's
// memory map, not guessed at:
//
//   - of usable memory, every page the allocator has handed out. Its own
//     bitmap is among them, and so are the tables this file keeps;
//   - all of what the boot loader marked reclaimable, which this kernel never
//     reclaims and still reads: the boot loader's answers, the command line,
//     the memory map itself;
//   - all of the kernel and its modules: the kernel's code and data, and the
//     initial filesystem, which files may still be read from in place.
//
// Free memory is not saved, nor anything that is not memory the kernel owns:
// firmware's regions, ACPI's tables, the framebuffer. A later boot has those
// again, and is compared with this one before the image is used
// (machine_amd64.v).
//
// The image has to be of one moment. So it is taken in two steps:
//
//  1. prepare(), while the machine still runs: the tables are made and a free
//     page is taken for every page that will be saved, with some to spare. If
//     memory is too full for that, the page cache is asked to give back what
//     it can have again, and if it is still too full hibernation is refused.
//  2. take_snapshot(), on one processor with interrupts off and every other
//     processor parked, called where a suspend to RAM would ask firmware for
//     the sleep, with the processor already saved: the pages to save are
//     listed, and each is copied into one of the pages taken for it.
//
// What is in the copies is then the machine as it was at that moment, the
// saved processor included, and the kernel goes on running. The page being
// copied last is as good as the one copied first, since nothing else runs in
// between -- but the copying itself changes memory: its own stack, and what
// it writes into the tables. Nothing the kernel inside the image will read
// is written after the copying starts.
//
// write_image() puts the copies on the device with the machine up again.
// The header goes last, after the pages are flushed, and is read back.
// Before anything else is written the device is given a header that
// describes no image, so that an old image cannot be entered once it has
// been written over in part.
//
// Everything taken here is given back by release(), on every path: after the
// image is written if the machine then fails to switch off, when writing
// fails, and by the kernel inside the image when it wakes.
@[has_globals]
module hibernate

import block.fence
import devcore
import fs
import limine
import memory
import x86.wake

// Pages kept free beyond the copies, for the kernel to go on running while
// it writes them.
const spare_pages = u64(2048)
// The most pages moved to the device at once.
const most_chunk_pages = u64(256)

__global (
	// The frames saved, ascending, and the frame each one's copy is in.
	hib_origs  Words
	hib_copies Words
	// A bit for every frame the allocator has: it holds one of the copies.
	hib_copy_bits Words
	// How many pages the tables have room for, how many copies are taken,
	// and how many pages the snapshot came to.
	hib_capacity u64
	hib_held     u64
	hib_count    u64
	// The page the loading kernel writes its report into, by address.
	hib_handover u64
	// What the image is written through: a run of pages to gather pages in,
	// how long it is, and two pages for the header and its reading back.
	// Taken before the snapshot, like everything else the writing needs:
	// after it, a request for memory that had the page cache give some back
	// could wait for a lock whose holder is being held at the fence.
	hib_buffer       u64
	hib_buffer_pages u64
	hib_scratch      u64
	// The machine as it was when the copies were prepared, and the clock.
	hib_machine  Machine
	hib_taken_at u64
	// Set in the kernel that takes the snapshot once the last page has been
	// copied, so never seen set by the kernel inside the image.
	hib_taken u32
	// How long the copying took.
	hib_copy_ns u64
	// Why the last attempt failed, and whether it left the device in a
	// state nobody knows.
	hib_failure      string
	hib_write_unsure bool
	// Images this kernel has written, and times it has woken from one.
	hib_sequence u64
	hib_resumes  u64
	// The last image written: its pages, its bytes on the device, and how
	// long writing took.
	hib_last_pages    u64
	hib_last_bytes    u64
	hib_last_write_ns u64
	hib_last_copy_ns  u64
	// What the kernel that loaded the last image said.
	hib_loader Handover
)

fn fail(why string) bool {
	hib_failure = why
	C.kprintf(c'hibernate: %.*s\n', i32(why.len), why.str)
	return false
}

// Why the last prepare(), take_snapshot() or write_image() failed.
pub fn failure() string {
	return hib_failure
}

// The pages of the boot loader's and the kernel's own regions, which are
// saved whole.
fn fixed_pages() u64 {
	mut pages := u64(0)
	for index in u64(0) .. map_entries() {
		base, length, kind := map_entry(index)
		if is_ram(kind) && kind != u64(limine.limine_memmap_usable) {
			pages += (base + length + page_size - 1) / page_size - base / page_size
		}
	}
	return pages
}

// Look at the device once more, while it can still be read: before the
// devices are suspended, and so before prepare(). False, with the reason
// kept, when it is not there or has been given to something else since it
// was last looked at.
pub fn device_ready() bool {
	hib_failure = ''
	if hib_device == unsafe { nil } {
		return fail(unavailable_reason())
	}
	if !device_is_ours() {
		return fail(hib_device_problem)
	}
	return true
}

// Make the tables and take a page for every page that will be saved. False,
// with nothing left taken, when there is no room. The devices are suspended
// by now, the image's among them: nothing here reads or writes it.
// Interrupts on, the machine running.
pub fn prepare() bool {
	hib_failure = ''
	release()
	if fs.block_encryption_used() { return fail('block encryption was used; an unencrypted memory image is prohibited for this boot') }
	if page_size != block_bytes {
		return fail('pages are not the size the image is written in')
	}
	if hib_device == unsafe { nil } || !hib_device_ours {
		return fail(unavailable_reason())
	}
	device_pages := hib_device_bytes / block_bytes
	fixed := fixed_pages()
	mut wanted := memory.pmm_frames_used() + fixed
	if image_bytes(wanted) > hib_device_bytes {
		// What the page cache can read again need not be in the image.
		memory.pmm_reclaim(wanted - (device_pages - device_pages / 8))
		wanted = memory.pmm_frames_used() + fixed
		if image_bytes(wanted) > hib_device_bytes {
			C.kprintf(c'hibernate: %llu pages are in use and the device has room for %llu\n',
				wanted, device_pages)
			return fail('the image would not fit on the device named for it')
		}
	}
	// More than is in use now: preparing takes memory itself, and the
	// machine runs on until the snapshot.
	capacity := wanted + wanted / 16 + spare_pages
	// Is there room for that many copies, and the tables, with pages to
	// spare? Asked before any is taken: taking them one by one until the
	// allocator is empty would find out as well, and stop the machine in
	// passing, since much of the kernel does not take no for an answer.
	need := capacity + capacity / 128 + most_chunk_pages + 2 * spare_pages
	if memory.pmm_frames_free() < need {
		memory.pmm_reclaim(need - memory.pmm_frames_free())
		if memory.pmm_frames_free() < need {
			C.kprintf(c'hibernate: %llu pages are in use and %llu are free\n', wanted, memory.pmm_frames_free())
			return fail('not enough free memory to hold a copy of what is in use')
		}
	}
	hib_origs = words_new(capacity) or { return fail('no memory for the list of pages to save') }
	hib_copies = words_new(capacity) or {
		release()
		return fail('no memory for the list of pages to save')
	}
	hib_copy_bits = words_new(memory.pmm_page_count() / 64 + 1) or {
		release()
		return fail('no memory for the list of pages to save')
	}
	hib_handover = one_page()
	hib_scratch = u64(memory.pmm_alloc_fallible(2))
	hib_buffer, hib_buffer_pages = chunk_buffer()
	if hib_handover == 0 || hib_scratch == 0 || hib_buffer == 0 {
		release()
		return fail('no memory for the list of pages to save')
	}
	hib_capacity = capacity
	for index in u64(0) .. capacity {
		// One at a time: free memory is in pieces. When there is none the
		// allocator has the page cache give some back before it gives up.
		frame := u64(memory.pmm_alloc_nozero_fallible(1)) / page_size
		if frame == 0 {
			release()
			return fail('not enough free memory to hold a copy of what is in use')
		}
		hib_copies.set(index, frame)
		hib_copy_bits.set_bit(frame)
		hib_held = index + 1
	}
	if memory.pmm_frames_free() < spare_pages {
		release()
		return fail('not enough free memory to hold a copy of what is in use')
	}
	hib_machine = this_machine()
	wake.trace('disk: prepared, room for pages', capacity)
	return true
}

// When the image is taken, by the battery-backed clock: for the header.
pub fn set_taken_at(seconds u64) {
	hib_taken_at = seconds
}

// The snapshot. One processor, interrupts off, the others parked, the
// processor's registers already saved; called once. On return either
// snapshot_taken() is true and the copies hold the machine as it was when
// this was called, or failure() says why not. Allocates nothing.
pub fn take_snapshot() {
	hib_count = 0
	hib_taken = 0
	if fs.block_encryption_used() { fail('block encryption was used; an unencrypted memory image is prohibited for this boot'); return }
	started := devcore.now_ns()
	frames := memory.pmm_page_count()
	mut count := u64(0)
	mut last := u64(0)
	for index in u64(0) .. map_entries() {
		base, length, kind := map_entry(index)
		if !is_ram(kind) {
			continue
		}
		usable := kind == u64(limine.limine_memmap_usable)
		// The allocator has the whole pages of usable memory; of the other
		// regions every page they touch is theirs.
		mut first := base / page_size
		mut end := (base + length + page_size - 1) / page_size
		if usable {
			first = (base + page_size - 1) / page_size
			end = (base + length) / page_size
			if end > frames {
				end = frames
			}
		}
		for frame := first; frame < end; frame++ {
			if usable && (!memory.pmm_frame_taken(frame) || hib_copy_bits.bit(frame)) {
				continue
			}
			if count != 0 && frame <= last {
				hib_failure = 'the memory map is not in order'
				return
			}
			if count == hib_capacity {
				hib_failure = 'more memory came into use while the copy was being prepared'
				return
			}
			hib_origs.set(count, frame)
			last = frame
			count++
		}
	}
	// From here on nothing is written that the kernel inside the image
	// reads: only the copies, this function's own stack, and what the
	// kernel that goes on running needs.
	hib_count = count
	wake.trace('disk: pages to copy', count)
	for index in u64(0) .. count {
		unsafe {
			C.memcpy(voidptr(hib_copies.get(index) * page_size + higher_half), voidptr(
				hib_origs.get(index) * page_size + higher_half), page_size)
		}
	}
	hib_copy_ns = devcore.now_ns() - started
	hib_taken = 1
	// And from here on nothing reaches a disk but the image: what this
	// kernel writes after the snapshot, the image knows nothing of.
	fence.raise()
}

// Whether take_snapshot() took one. True only in the kernel that took it.
pub fn snapshot_taken() bool {
	return hib_taken != 0
}

// A run of pages to move through, as long as can be had. 0, 0 when not one.
fn chunk_buffer() (u64, u64) {
	mut pages := most_chunk_pages
	for pages != 0 {
		buffer := u64(memory.pmm_alloc_nozero_fallible(pages))
		if buffer != 0 {
			return buffer, pages
		}
		pages /= 4
	}
	return 0, 0
}

pub enum Written {
	// The device holds a whole image whose header read back as written.
	image
	// It holds none: a header that describes no image was written and read
	// back, and no other header after it.
	nothing
	// It may hold either. The last header was written and could not be
	// confirmed, and could not be replaced. Whoever asked must not let
	// this kernel go on changing the disks: if the image is there, it is
	// an image of them as they are now.
	unknown
}

// Put the snapshot on the device, and say what the device then holds. The
// machine is up, userspace frozen.
pub fn write_image() Written {
	if write_snapshot() {
		return .image
	}
	return if hib_write_unsure { Written.unknown } else { Written.nothing }
}

fn write_snapshot() bool {
	hib_write_unsure = false
	if hib_taken == 0 || hib_count == 0 {
		return fail('there is no snapshot to write')
	}
	started := devcore.now_ns()
	pages := hib_count
	if image_bytes(pages) > hib_device_bytes {
		C.kprintf(c'hibernate: the image is %llu pages and the device has room for %llu\n',
			pages, hib_device_bytes / block_bytes)
		return fail('the image does not fit on the device named for it')
	}
	// First: whatever image the device has can no longer be entered.
	if !write_empty_header(hib_sequence) {
		return fail('the device named for the image cannot be written')
	}
	mut header := new_header(pages, hib_sequence + 1)

	// The frame numbers are in pages of their own already.
	mut list_sum := image_magic
	leaves := (pages + words_per_page - 1) / words_per_page
	for leaf in u64(0) .. leaves {
		page := hib_origs.leaf_page(leaf)
		here := if pages - leaf * words_per_page < words_per_page {
			pages - leaf * words_per_page
		} else {
			words_per_page
		}
		list_sum = sum_words(list_sum, page_of(page), here)
		if !device_write(header.list_offset + leaf * block_bytes, voidptr(page + higher_half),
			block_bytes) {
			return fail('writing the image failed')
		}
	}

	buffer := hib_buffer
	chunk := hib_buffer_pages
	if buffer == 0 || chunk == 0 {
		return fail('no memory to write the image through')
	}
	mut data_sum := image_magic
	mut done := u64(0)
	for done < pages {
		count := if pages - done < chunk { pages - done } else { chunk }
		for index in u64(0) .. count {
			copy := hib_copies.get(done + index) * page_size
			data_sum = sum_words(data_sum, page_of(copy), words_per_page)
			unsafe {
				C.memcpy(voidptr(buffer + index * page_size + higher_half), voidptr(copy +
					higher_half), page_size)
			}
		}
		if !device_write(header.data_offset + done * block_bytes, voidptr(buffer + higher_half),
			count * block_bytes) {
			return fail('writing the image failed')
		}
		done += count
	}
	wake.trace('disk: pages written', pages)
	if !device_flush() {
		return fail('the device would not keep the image')
	}

	header.list_checksum = list_sum
	header.data_checksum = data_sum
	header.entry = wake.resume_entry()
	header.context = wake.context_address()
	header.handover = hib_handover / page_size
	header.taken_at = hib_taken_at
	header.copy_time = hib_copy_ns
	header.write_time = devcore.now_ns() - started
	header.machine = hib_machine
	seal(mut header)
	// Last, and read back: this block is what makes the rest an image.
	if !write_header(header) {
		// It may be there, in part or whole: the write, the flush or the
		// reading back failed. It is taken back; and if that fails too,
		// nobody knows what the device holds.
		if !write_empty_header(hib_sequence) {
			hib_write_unsure = true
			return fail('the header of the image could not be confirmed, nor taken back')
		}
		return fail('the header of the image did not read back as written')
	}
	hib_sequence++
	hib_last_pages = pages
	hib_last_bytes = header.end_offset
	hib_last_copy_ns = hib_copy_ns
	hib_last_write_ns = devcore.now_ns() - started
	C.kprintf(c'hibernate: image of %llu pages written in %llu ms\n', pages, hib_last_write_ns / devcore.millisecond)
	return true
}

// The image that was just written is not going to be used: the machine did
// not switch off. Take it back, so that it cannot be entered later, after
// this kernel has gone on and changed what it describes.
pub fn withdraw_image() bool {
	return write_empty_header(hib_sequence)
}

// Give back the copies and the tables, and let writes to disks through
// again. For every way out: nothing is held after it, and it may be called
// with nothing held.
pub fn release() {
	for index in u64(0) .. hib_held {
		memory.pmm_free(voidptr(hib_copies.get(index) * page_size), 1)
	}
	hib_held = 0
	hib_capacity = 0
	hib_count = 0
	hib_taken = 0
	hib_origs.release()
	hib_copies.release()
	hib_copy_bits.release()
	if hib_handover != 0 {
		memory.pmm_free(voidptr(hib_handover), 1)
		hib_handover = 0
	}
	if hib_scratch != 0 {
		memory.pmm_free(voidptr(hib_scratch), 2)
		hib_scratch = 0
	}
	if hib_buffer != 0 {
		memory.pmm_free(voidptr(hib_buffer), hib_buffer_pages)
		hib_buffer = 0
		hib_buffer_pages = 0
	}
	if fence.raised() {
		fence.lower()
	}
}

// This kernel has just been entered from an image: read what the kernel
// that loaded it left, count the wake, and give back what the snapshot held.
pub fn resumed() {
	if hib_handover != 0 {
		report := unsafe { &Handover(hib_handover + higher_half) }
		if report.magic == handover_magic {
			hib_loader = *report
		}
	}
	hib_resumes++
	// The kernel that wrote the image counted it; this one was not there.
	hib_sequence++
	hib_last_pages = hib_count
	hib_last_bytes = hib_loader.image_bytes
	hib_last_copy_ns = hib_loader.copy_time
	hib_last_write_ns = hib_loader.write_time
	release()
}
