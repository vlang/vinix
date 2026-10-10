// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What an image is on its device, and when its header is believed:
// kernel/hibernate/format.v, on the host.
module hibernate

const device = u64(64) << 20

fn sample_machine() Machine {
	return Machine{
		kernel_virtual:     0xffffffff80000000
		kernel_physical:    0x37fe2000
		kernel_bytes:       0xb82000
		kernel_digest:      0x177d2ace54b0d918
		direct_map:         0xff00000000000000
		paging_levels:      5
		map_memory:         0xbb2eb1de8f0f3074
		map_fixed:          0x13a727e0ad71abac
		memory_top:         0x40000000
		acpi_root:          0xff0000003fb7e014
		acpi_tables:        0x67c23d157a93a291
		framebuffer:        0xff00000080000000
		framebuffer_layout: 0xabb7314c77898a44
		processors:         4
		processor_digest:   0xa8beea74343eeb2a
		command_line:       0x402a470928f955d6
		disks:              0x5d1c9f0b3e7a6c21
		low_base:           0x98000
		low_pages:          8
	}
}

fn sample_header(pages u64) Header {
	mut header := new_header(pages, 3)
	header.list_checksum = 11
	header.data_checksum = 22
	header.entry = 0xffffffff802ef840
	header.context = 0xffffffff80a00000
	header.handover = 0x1234
	header.taken_at = 1791664809
	header.machine = sample_machine()
	seal(mut header)
	return header
}

fn bytes_of(header &Header) []u8 {
	mut bytes := []u8{len: int(sizeof(Header))}
	unsafe { vmemcpy(bytes.data, voidptr(header), int(sizeof(Header))) }
	return bytes
}

fn header_of(bytes []u8) Header {
	mut header := Header{}
	unsafe { vmemcpy(voidptr(&header), bytes.data, int(sizeof(Header))) }
	return header
}

fn test_the_signatures_are_text() {
	magic := image_magic
	assert unsafe { tos(&u8(&magic), 8) } == 'VINIXHIB'
	handover := handover_magic
	assert unsafe { tos(&u8(&handover), 8) } == 'HANDOVER'
}

fn test_a_header_is_whole_words_and_fits_its_block() {
	assert sizeof(Header) % 8 == 0
	assert sizeof(Header) <= block_bytes
	assert sizeof(Handover) <= block_bytes
	// The number of pages is where the tests on the host look for it.
	assert __offsetof(Header, pages) == 24
}

fn test_where_the_parts_of_an_image_are() {
	assert list_bytes(0) == 0
	assert list_bytes(1) == 4096
	assert list_bytes(512) == 4096
	assert list_bytes(513) == 8192
	assert image_bytes(1) == 4096 + 4096 + 4096
	assert image_bytes(1000) == 4096 + 8192 + 1000 * 4096
	header := new_header(1000, 0)
	assert header.list_offset == 4096
	assert header.data_offset == 4096 + 8192
	assert header.end_offset == image_bytes(1000)
}

fn test_a_sealed_header_for_pages_is_an_image() {
	header := sample_header(1000)
	verdict, why := judge_header(&header, device)
	assert verdict == .image
	assert why == ''
}

fn test_a_header_for_no_pages_is_a_claimed_device_with_no_image() {
	mut header := new_header(0, 7)
	seal(mut header)
	verdict, _ := judge_header(&header, device)
	assert verdict == .empty
	// Whatever else it says: no pages is no image.
	mut entered := sample_header(1000)
	entered.pages = 0
	seal(mut entered)
	second, _ := judge_header(&entered, device)
	assert second == .empty
}

fn test_anything_else_is_not_this_systems() {
	blank := Header{}
	verdict, _ := judge_header(&blank, device)
	assert verdict == .foreign
	mut other := sample_header(1000)
	other.magic = 0x5346544e // "NTFS", say
	second, _ := judge_header(&other, device)
	assert second == .foreign
}

fn test_every_bit_of_a_header_counts() {
	good := bytes_of(sample_header(1000))
	for index in 0 .. good.len {
		for bit in 0 .. 8 {
			mut bytes := good.clone()
			bytes[index] ^= u8(1) << bit
			header := header_of(bytes)
			verdict, _ := judge_header(&header, device)
			// A changed signature is another system's device; any other
			// change is a header that cannot be believed. Neither is an
			// image, and neither is an empty device this system may take.
			if index < 8 {
				assert verdict == .foreign
			} else {
				assert verdict == .damaged, 'bit ${bit} of byte ${index} changed and the header is ${verdict}'
			}
		}
	}
}

fn test_a_header_that_cannot_be_is_damaged_though_its_checksum_holds() {
	mut longer := sample_header(1000)
	verdict, why := judge_header(&longer, image_bytes(1000) - 1)
	assert verdict == .damaged
	assert why.contains('longer than the device')
	exact, _ := judge_header(&longer, image_bytes(1000))
	assert exact == .image

	mut moved := sample_header(1000)
	moved.data_offset += 4096
	seal(mut moved)
	second, reason := judge_header(&moved, device)
	assert second == .damaged
	assert reason.contains('cannot be')

	mut future := sample_header(1000)
	future.version = format_version + 1
	seal(mut future)
	third, format := judge_header(&future, device)
	assert third == .damaged
	assert format.contains('format')

	mut nowhere := sample_header(1000)
	nowhere.entry = 0
	seal(mut nowhere)
	fourth, entry := judge_header(&nowhere, device)
	assert fourth == .damaged
	assert entry.contains('enter')

	mut huge := sample_header(1000)
	huge.pages = u64(1) << 60
	seal(mut huge)
	fifth, _ := judge_header(&huge, device)
	assert fifth == .damaged
}

fn test_the_checksum_tells_bytes_order_and_length_apart() {
	a := 'the quick brown fox jumps over the lazy dog'.bytes()
	mut b := a.clone()
	b[20] ^= 1
	assert sum_bytes(image_magic, a.data, u64(a.len)) != sum_bytes(image_magic, b.data, u64(b.len))
	// A zero more at the end is another text.
	zeros := []u8{len: 24}
	assert sum_bytes(image_magic, zeros.data, 16) != sum_bytes(image_magic, zeros.data, 17)
	assert sum_bytes(image_magic, zeros.data, 16) != sum_bytes(image_magic, zeros.data, 24)
	// Two pages the other way round are another image.
	first := [u64(1), 2, 3, 4]
	second := [u64(5), 6, 7, 8]
	forward := sum_words(sum_words(image_magic, first.data, 4), second.data, 4)
	backward := sum_words(sum_words(image_magic, second.data, 4), first.data, 4)
	assert forward != backward
	// And the same again is the same.
	assert forward == sum_words(sum_words(image_magic, first.data, 4), second.data, 4)
}

fn test_the_same_machine_may_enter() {
	image := sample_machine()
	here := sample_machine()
	assert machine_difference(&image, &here) == ''
}

fn test_where_the_boot_loader_put_the_kernel_is_not_compared() {
	image := sample_machine()
	mut here := sample_machine()
	here.kernel_physical += 0x10000
	assert machine_difference(&image, &here) == ''
}

fn test_every_other_difference_is_named() {
	image := sample_machine()
	mut here := sample_machine()
	here.kernel_digest++
	assert machine_difference(&image, &here).contains('another kernel')
	here = sample_machine()
	here.kernel_bytes += 4096
	assert machine_difference(&image, &here).contains('another kernel')
	here = sample_machine()
	here.command_line++
	assert machine_difference(&image, &here).contains('command line')
	here = sample_machine()
	here.disks++
	assert machine_difference(&image, &here).contains('disks')
	// Named before the memory: a disk more moves firmware's memory too, and
	// the disk is the reason somebody can do something about.
	here.map_memory++
	here.map_fixed++
	assert machine_difference(&image, &here).contains('disks')
	here = sample_machine()
	here.map_memory++
	assert machine_difference(&image, &here).contains('memory of the machine')
	here = sample_machine()
	here.memory_top -= 0x10000000
	assert machine_difference(&image, &here).contains('memory of the machine')
	here = sample_machine()
	here.map_fixed++
	assert machine_difference(&image, &here).contains('firmware')
	here = sample_machine()
	here.kernel_virtual += 0x200000
	assert machine_difference(&image, &here).contains('mapped somewhere else')
	here = sample_machine()
	here.direct_map += 0x40000000
	assert machine_difference(&image, &here).contains('address space')
	here = sample_machine()
	here.paging_levels = 4
	assert machine_difference(&image, &here).contains('address space')
	here = sample_machine()
	here.processors = 2
	assert machine_difference(&image, &here).contains('processors')
	here = sample_machine()
	here.processor_digest++
	assert machine_difference(&image, &here).contains('processors')
	here = sample_machine()
	here.acpi_root += 16
	assert machine_difference(&image, &here).contains('ACPI')
	here = sample_machine()
	here.acpi_tables++
	assert machine_difference(&image, &here).contains('ACPI')
	here = sample_machine()
	here.framebuffer += 4096
	assert machine_difference(&image, &here).contains('display')
	here = sample_machine()
	here.framebuffer_layout++
	assert machine_difference(&image, &here).contains('display')
	here = sample_machine()
	here.low_base -= 4096
	assert machine_difference(&image, &here).contains('processors start on')
}
