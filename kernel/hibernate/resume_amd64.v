// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Going back into an image, from the kernel that finds it at boot.
//
// resume_at_boot() is called once, when the disk drivers have brought their
// disks up and before anything on a disk is mounted. The kernel inside an
// image has every mounted filesystem's state in its memory; a boot that
// mounted one of them first, replayed its journal or wrote to it, and then
// went back into the image would leave a kernel running on a disk that is
// no longer what it remembers. So the order is fixed, and it is checked too:
// block drivers count the writes they are asked for (block/fence), and an
// image is not entered by a kernel that has made any.
//
// A device with a whole image on it leads to one of two things, and to
// nothing else. Either this machine is the machine the image was taken on in
// every way that matters (format.v lists them), the image reads back
// complete, and it is entered. Or it is not entered, the reason is said, and
// the device is given a header that describes no image, so that the image is
// never entered later either -- by then the disks will have moved on. That
// header is also written just before an image is entered: an image is
// entered once.
//
// Loading. The image's pages each belong in the frame they were saved from.
//
//   - A frame that is free in this kernel is taken from the allocator by
//     number and the page is read straight into it.
//   - A frame this kernel is using -- its own code and data are in the same
//     frames as the image's kernel's, to begin with -- cannot be written
//     yet. The page is read into some other frame, one the image does not
//     want at all, and the two are written down as a pair.
//
// When every page is in memory and the checksum of the whole agrees, the
// devices are stopped so that nothing writes to memory behind the
// processor's back, the other processors are parked, and with interrupts
// off the last step is taken by code that does not depend on this kernel's
// memory any more (asm/x86_64/hibernate.S): on a page table made for it, it
// copies the pairs into place and jumps to the image's entry -- the one a
// processor woken from a suspend to RAM arrives at. That page table, the
// list of pairs, the code and its stack are all in frames the image does not
// want, so the copying cannot overwrite what it is working from.
//
// From the entry on it is the image's kernel that runs, on the way back from
// a sleep in which everything lost power (syspower/hibernate_amd64.v).
//
// Nothing here is left allocated on a way out that does not enter the image.
@[has_globals]
module hibernate

import block.fence
import devcore
import dma
import katomic
import limine
import memory
import proc
import sched
import x86.apic
import x86.cpu
import x86.hypervisor
import x86.wake

fn C.x86_hibernate_enter(block voidptr)
fn C.x86_hibernate_copy()
fn C.x86_hibernate_copy_end()

// asm/x86_64/hibernate.S addresses this by offset.
struct Jump {
mut:
	cr3        u64
	cr4        u64
	stack      u64
	copy       u64
	list       u64
	direct_map u64
	entry      u64
	context    u64
}

const cr4_pae = u64(1) << 5
const cr4_la57 = u64(1) << 12
const pte_large = u64(1) << 7
const pte_address = u64(0x000ffffffffff000)
const large_bytes = u64(2) << 20
const move_timeout_ns = 2 * devcore.second

// A list of words kept in a chain of pages: the address of the next page, how
// many words this one holds, then the words. The last step of a resume reads
// one of these with nothing else to go by.
const chain_words = u64(510)

struct Chain {
mut:
	head u64
	tail u64
}

fn (chain &Chain) full() bool {
	return chain.tail == 0 || unsafe { page_of(chain.tail)[1] } >= chain_words
}

// Give the chain another page, which must be zero.
fn (mut chain Chain) extend(page u64) {
	if chain.tail == 0 {
		chain.head = page
	} else {
		unsafe {
			mut last := page_of(chain.tail)
			last[0] = page
		}
	}
	chain.tail = page
}

// Only when not full().
fn (mut chain Chain) push(value u64) {
	unsafe {
		mut page := page_of(chain.tail)
		page[2 + page[1]] = value
		page[1]++
	}
}

struct Loader {
mut:
	header Header
	// The frames the image wants, as on the device; a bit for each frame it
	// wants; and a bit for each that was free here and has been taken.
	origs  Words
	wanted Words
	direct Words
	// One past the highest frame it wants.
	frames u64
	// Pairs for the last step: where a page belongs, where it waits.
	pairs Chain
	// Frames taken that are not in the pairs: for the page table, the code,
	// its stack. And frames the allocator gave that the image wants and that
	// were not free when its frames were taken: kept out of the way.
	extra Chain
	aside Chain
	// The page table for the last step.
	top u64
	// Where the image's page for the report is now.
	handover_at u64
	direct_pages    u64
	relocated_pages u64
	started         u64
}

__global (
	// What happened when this kernel looked for an image at boot: '' when it
	// did not look or found none, else why the image it found was not
	// entered.
	hib_boot_verdict string
	hib_boot_looked  bool
	hib_boot_found   bool
)

// What the look for an image at boot came to, for /sys.
pub fn boot_verdict() (bool, bool, string) {
	return hib_boot_looked, hib_boot_found, hib_boot_verdict
}

fn zero_page(page u64) {
	unsafe { C.memset(voidptr(page + higher_half), 0, page_size) }
}

// A frame the image does not want, by address. 0 when memory has run out.
fn (mut loader Loader) take_frame() u64 {
	for {
		page := u64(memory.pmm_alloc_nozero_fallible(1))
		if page == 0 {
			return 0
		}
		frame := page / page_size
		if frame >= loader.frames || !loader.wanted.bit(frame) {
			return page
		}
		// The image wants this one, and it was in use when the image's
		// frames were taken, so its page will be copied into it at the end.
		// It cannot hold anything until then; keep it from being handed out
		// again and ask for another.
		if loader.aside.full() {
			link := one_page()
			if link == 0 {
				memory.pmm_free(voidptr(page), 1)
				return 0
			}
			loader.aside.extend(link)
		}
		loader.aside.push(page)
	}
	return 0
}

// A frame for the last step that is not one of a pair.
fn (mut loader Loader) take_extra() u64 {
	if loader.extra.full() {
		link := one_page()
		if link == 0 {
			return 0
		}
		loader.extra.extend(link)
	}
	page := loader.take_frame()
	if page == 0 {
		return 0
	}
	zero_page(page)
	loader.extra.push(page)
	return page
}

fn free_chain(mut chain Chain, entries bool) {
	mut page := chain.head
	for page != 0 {
		words := page_of(page)
		next := unsafe { words[0] }
		if entries {
			for index in u64(0) .. unsafe { words[1] } {
				memory.pmm_free(voidptr(unsafe { words[2 + index] }), 1)
			}
		}
		memory.pmm_free(voidptr(page), 1)
		page = next
	}
	chain.head = 0
	chain.tail = 0
}

// Give back everything taken. The image is not going to be entered.
fn (mut loader Loader) release() {
	// The pairs: the second word of each is a frame that was taken; the
	// first is where the page belongs, which was never ours.
	mut page := loader.pairs.head
	for page != 0 {
		words := page_of(page)
		next := unsafe { words[0] }
		for index := u64(1); index < unsafe { words[1] }; index += 2 {
			memory.pmm_free(voidptr(unsafe { words[2 + index] }), 1)
		}
		memory.pmm_free(voidptr(page), 1)
		page = next
	}
	loader.pairs = Chain{}
	free_chain(mut loader.extra, true)
	free_chain(mut loader.aside, true)
	// The frames read straight into.
	if loader.direct.root != 0 && loader.origs.root != 0 {
		for index in u64(0) .. loader.header.pages {
			frame := loader.origs.get(index)
			if frame < loader.frames && loader.direct.bit(frame) {
				memory.pmm_free(voidptr(frame * page_size), 1)
			}
		}
	}
	loader.origs.release()
	loader.wanted.release()
	loader.direct.release()
}

// Whether every frame the image wants is memory this kernel has, each in
// one piece and in ascending order. The memory map was compared already; this
// is the same question asked of each page, since a page put where there is
// no memory, or where firmware lives, cannot be taken back.
fn (loader &Loader) frames_are_memory() bool {
	entries := map_entries()
	limit := memory.pmm_page_count()
	mut entry := u64(0)
	mut previous := u64(0)
	for index in u64(0) .. loader.header.pages {
		frame := loader.origs.get(index)
		if index != 0 && frame <= previous {
			return false
		}
		previous = frame
		start := frame * page_size
		mut found := false
		for entry < entries {
			base, length, kind := map_entry(entry)
			if start + page_size <= base {
				return false
			}
			if start >= base + length {
				entry++
				continue
			}
			if !is_ram(kind) {
				return false
			}
			if kind == u64(limine.limine_memmap_usable) && (start < base || start + page_size > base + length
				|| frame >= limit) {
				return false
			}
			found = true
			break
		}
		if !found {
			return false
		}
	}
	return true
}

// Read the frame numbers from the device into a table and check them.
fn (mut loader Loader) read_list() string {
	pages := loader.header.pages
	loader.origs = words_new(pages) or { return 'there is no memory to load it' }
	mut sum := image_magic
	leaves := (pages + words_per_page - 1) / words_per_page
	for leaf in u64(0) .. leaves {
		page := loader.origs.leaf_page(leaf)
		if !device_read(loader.header.list_offset + leaf * block_bytes, voidptr(page + higher_half),
			block_bytes) {
			return 'the device could not be read'
		}
		here := if pages - leaf * words_per_page < words_per_page {
			pages - leaf * words_per_page
		} else {
			words_per_page
		}
		sum = sum_words(sum, page_of(page), here)
	}
	if sum != loader.header.list_checksum {
		return 'its list of pages does not match its checksum'
	}
	if !loader.frames_are_memory() {
		return 'it has pages for memory this machine does not have'
	}
	loader.frames = loader.origs.get(pages - 1) + 1
	loader.wanted = words_new(loader.frames / 64 + 1) or { return 'there is no memory to load it' }
	loader.direct = words_new(loader.frames / 64 + 1) or { return 'there is no memory to load it' }
	for index in u64(0) .. pages {
		loader.wanted.set_bit(loader.origs.get(index))
	}
	return ''
}

// Take every frame the image wants that is free, and read the pages in:
// into their frames where those were free, elsewhere where not.
fn (mut loader Loader) read_pages() string {
	pages := loader.header.pages
	for index in u64(0) .. pages {
		frame := loader.origs.get(index)
		if memory.pmm_claim_frame(frame) {
			loader.direct.set_bit(frame)
		}
	}
	buffer, chunk := chunk_buffer()
	if buffer == 0 {
		return 'there is no memory to load it'
	}
	defer {
		memory.pmm_free(voidptr(buffer), chunk)
	}
	mut sum := image_magic
	mut done := u64(0)
	for done < pages {
		count := if pages - done < chunk { pages - done } else { chunk }
		if !device_read(loader.header.data_offset + done * block_bytes, voidptr(buffer + higher_half),
			count * block_bytes) {
			return 'the device could not be read'
		}
		for index in u64(0) .. count {
			source := buffer + index * page_size
			frame := loader.origs.get(done + index)
			sum = sum_words(sum, page_of(source), words_per_page)
			mut place := frame * page_size
			if loader.direct.bit(frame) {
				loader.direct_pages++
			} else {
				if loader.pairs.full() {
					link := loader.take_frame()
					if link == 0 {
						return 'there is no memory to load it'
					}
					zero_page(link)
					loader.pairs.extend(link)
				}
				place = loader.take_frame()
				if place == 0 {
					return 'there is no memory to load it'
				}
				// Both words at once: a pair is never half there.
				loader.pairs.push(frame * page_size)
				loader.pairs.push(place)
				loader.relocated_pages++
			}
			unsafe { C.memcpy(voidptr(place + higher_half), voidptr(source + higher_half), page_size) }
			if frame == loader.header.handover {
				loader.handover_at = place
			}
		}
		done += count
	}
	if sum != loader.header.data_checksum {
		return 'its pages do not match its checksum'
	}
	if loader.handover_at == 0 {
		return 'its header does not say how to enter it'
	}
	return ''
}

fn (mut loader Loader) next_table(table u64, index u64) u64 {
	mut entries := page_of(table)
	if unsafe { entries[index] } & memory.pte_present == 0 {
		page := loader.take_extra()
		if page == 0 {
			return 0
		}
		unsafe {
			entries[index] = page | memory.pte_present | memory.pte_writable
		}
	}
	return unsafe { entries[index] } & pte_address
}

// Map `virt` to `phys` in the page table for the last step: one page, or two
// megabytes with `large`.
fn (mut loader Loader) map(virt u64, phys u64, large bool) bool {
	levels := if la57 { 5 } else { 4 }
	leaf := if large { 1 } else { 0 }
	mut table := loader.top
	for level := levels - 1; level > leaf; level-- {
		table = loader.next_table(table, (virt >> u64(12 + 9 * level)) & 0x1ff)
		if table == 0 {
			return false
		}
	}
	mut entries := page_of(table)
	unsafe {
		entries[(virt >> u64(12 + 9 * leaf)) & 0x1ff] = phys | memory.pte_present | memory.pte_writable | if large {
			pte_large
		} else {
			u64(0)
		}
	}
	return true
}

// The page table the last step runs under: all of memory where the direct
// map has it, and the kernel where the kernel is. Returns the block of
// values the last step works from, or 0.
fn (mut loader Loader) last_step() u64 {
	loader.top = loader.take_extra()
	if loader.top == 0 || higher_half % large_bytes != 0 {
		return 0
	}
	top := (ram_top() + large_bytes - 1) / large_bytes * large_bytes
	for phys := u64(0); phys < top; phys += large_bytes {
		if !loader.map(higher_half + phys, phys, true) {
			return 0
		}
	}
	machine := &loader.header.machine
	for offset := u64(0); offset < machine.kernel_bytes; offset += page_size {
		if !loader.map(machine.kernel_virtual + offset, machine.kernel_physical + offset,
			false) {
			return 0
		}
	}
	code := loader.take_extra()
	stack := loader.take_extra()
	block := loader.take_extra()
	if code == 0 || stack == 0 || block == 0 {
		return 0
	}
	start := u64(voidptr(C.x86_hibernate_copy))
	length := u64(voidptr(C.x86_hibernate_copy_end)) - start
	if length > page_size {
		return 0
	}
	unsafe { C.memcpy(voidptr(code + higher_half), voidptr(start), length) }
	mut jump := unsafe { &Jump(block + higher_half) }
	jump.cr3 = loader.top
	jump.cr4 = cr4_pae | if la57 { cr4_la57 } else { u64(0) }
	jump.stack = stack + page_size + higher_half
	jump.copy = code + higher_half
	jump.list = loader.pairs.head
	jump.direct_map = higher_half
	jump.entry = loader.header.entry
	jump.context = loader.header.context
	return block + higher_half
}

fn on_boot_cpu(context voidptr) bool {
	me := unsafe { &proc.Thread(context) }
	return katomic.load(&me.running_on) == 0
}

// Say why the image is not being entered, and see that it never is.
fn refuse(why string) {
	hib_boot_verdict = why
	C.kprintf(c'hibernate: the image on %.*s is not resumed: %.*s\n', i32(hib_device_name.len),
		hib_device_name.str, i32(why.len), why.str)
	if write_empty_header(0) {
		print('hibernate: the image is discarded; starting afresh\n')
	} else {
		// Nothing more can be done from here, and it matters: this boot is
		// about to change the disks the image describes.
		print('hibernate: THE IMAGE COULD NOT BE DISCARDED. It must not be resumed later: clear the device before the next start\n')
	}
}

// Look for an image on the named device and enter it if this machine is the
// one it was taken on. Returns when there is none to enter; does not return
// when there is.
pub fn resume_at_boot() {
	if device_name().len == 0 {
		return
	}
	hib_boot_looked = true
	if !open_device() {
		C.kprintf(c'hibernate: %.*s: %.*s\n', i32(hib_device_name.len), hib_device_name.str,
			i32(hib_device_problem.len), hib_device_problem.str)
		return
	}
	mut loader := &Loader(memory.calloc(1, sizeof(Loader)))
	if loader == unsafe { nil } {
		return
	}
	defer {
		unsafe { memory.free(loader) }
	}
	verdict, damage := read_header(mut loader.header)
	if verdict == .foreign || verdict == .empty {
		// No image. Whether one can be kept here is found out now, while
		// reading the device is all that is happening to it.
		if !device_is_ours() {
			C.kprintf(c'hibernate: %.*s: %.*s\n', i32(hib_device_name.len), hib_device_name.str,
				i32(hib_device_problem.len), hib_device_problem.str)
		}
		return
	}
	hib_boot_found = true
	hib_device_ours = true
	if verdict == .damaged {
		refuse(damage)
		return
	}
	loader.started = devcore.now_ns()
	// An image, whole as far as its header goes. May it be entered here?
	writes := fence.writes()
	if writes != 0 {
		refuse('this boot has already written to a disk')
		return
	}
	here := this_machine()
	difference := machine_difference(&loader.header.machine, &here)
	if difference.len != 0 {
		refuse(difference)
		return
	}
	if !wake.available() {
		refuse('this boot has nowhere to start the other processors from')
		return
	}
	// The same kernel has its entry at the same address; anything else is
	// not an address to jump to.
	if loader.header.entry != wake.resume_entry() || loader.header.context != wake.context_address() {
		refuse('it was taken by another kernel')
		return
	}
	mut problem := loader.read_list()
	if problem.len == 0 {
		problem = loader.read_pages()
	}
	mut block := u64(0)
	if problem.len == 0 {
		block = loader.last_step()
		if block == 0 {
			problem = 'there is no memory to load it'
		}
	}
	if problem.len != 0 {
		loader.release()
		refuse(problem)
		return
	}

	// What the kernel inside is told.
	mut report := unsafe { &Handover(loader.handover_at + higher_half) }
	unsafe { C.memset(voidptr(report), 0, sizeof(Handover)) }
	report.direct = loader.direct_pages
	report.relocated = loader.relocated_pages
	report.writes_before = writes
	report.copy_time = loader.header.copy_time
	report.write_time = loader.header.write_time
	report.image_bytes = loader.header.end_offset
	report.load_time = devcore.now_ns() - loader.started
	report.magic = handover_magic

	// An image is entered once. From here the device holds none, whether
	// the rest works or not.
	if !write_empty_header(loader.header.sequence) {
		loader.release()
		hib_boot_verdict = 'the device could not be written, so the image could not be marked as used'
		print('hibernate: the image is not resumed: it could not be marked as used. It must not be resumed later: clear the device before the next start\n')
		return
	}
	C.kprintf(c'hibernate: image of %llu pages loaded (%llu in place, %llu to move) in %llu ms; entering it\n',
		loader.header.pages, loader.direct_pages, loader.relocated_pages, report.load_time / devcore.millisecond)

	// Nothing may write to memory from now on but this processor: stop the
	// devices, on the processor the image was taken on.
	mut me := proc.current_thread()
	affinity := katomic.load(&me.affinity_mask)
	katomic.store(mut &me.affinity_mask, u64(1))
	sched.wake_cpu(0)
	mut stopped := ''
	if !devcore.sleep_until(on_boot_cpu, voidptr(me), move_timeout_ns, 1) {
		stopped = 'the loading thread could not move to the boot processor'
	} else if !devcore.pause_pci_hotplug() {
		stopped = 'a PCI hot-plug operation would not finish'
	} else {
		devcore.freeze_bindings()
		refused := devcore.suspend_all()
		if refused != unsafe { nil } {
			stopped = 'a device would not stop'
		} else if !wake.park_secondaries() {
			stopped = 'a processor would not stop'
			wake.start_secondaries()
			devcore.resume_all()
		}
		if stopped.len != 0 {
			devcore.thaw_bindings()
			devcore.resume_pci_hotplug()
		}
	}
	if stopped.len != 0 {
		katomic.store(mut &me.affinity_mask, affinity)
		loader.release()
		hib_boot_verdict = stopped
		C.kprintf(c'hibernate: the image is not resumed: %.*s. It is discarded; starting afresh\n',
			i32(stopped.len), stopped.str)
		return
	}
	cpu.interrupt_toggle(false)
	report.loader_uptime = devcore.now_ns()
	apic.lapic_timer_stop()
	// As after power-on, which is what the image's kernel expects to find:
	// no IOMMU translating through tables that are about to be overwritten,
	// and the processor out of VMX operation.
	dma.hand_over_units()
	hypervisor.leave_cpu(0)
	C.x86_hibernate_enter(voidptr(block))
	for {}
}
