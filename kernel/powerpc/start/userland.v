// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.cpu
import powerpc.elf32
import powerpc.exception
import powerpc.ramfs
import powerpc.runtime
import powerpc.serial

__global rootfs ramfs.Image

fn launch_init() {
	archive := startup_info.initramfs
	if archive.base == 0 {
		for {}
	}
	if !ramfs.parse(unsafe { &u8(archive.base) }, archive.size, mut rootfs) {
		halt(c'initramfs validation')
	}
	index := rootfs.find(unsafe { &u8(c'bin/init') }, 8)
	if index < 0 { halt(c'missing /bin/init') }
	file := rootfs.files[index]
	mut image := elf32.Image{}
	if !elf32.parse(file.data, file.size, mut image) { halt(c'init ELF32 validation') }
	for i := u32(0); i < image.count; i++ {
		segment := image.segments[i]
		end := segment.address + segment.memory_size
		if segment.address < 0x40000000 || end > 0x5ffe0000
			|| (segment.flags & 1 != 0 && end > 0x50000000)
			|| (segment.flags & 2 != 0 && segment.address < 0x50000000) {
			halt(c'init segment permissions')
		}
		for address := segment.address & ~u32(4095); address < end; address += 4096 {
			physical := physical_pages.take(1, 1)
			if physical == 0 { halt(c'init memory exhausted') }
			runtime.fill(voidptr(physical), 0, 4096)
			if !user_space.map(address, physical, segment.flags & 2 != 0) { halt(c'init mapping') }
		}
		mut copied := u32(0)
		for copied < segment.file_size {
			address := segment.address + copied
			mut count := 4096 - (address & 4095)
			if count > segment.file_size - copied { count = segment.file_size - copied }
			physical := user_space.translate(address, false)
			if physical == 0 { halt(c'init segment copy') }
			runtime.copy(voidptr(physical), unsafe { &file.data[segment.offset + copied] }, count)
			copied += count
		}
	}
	for i := u32(0); i < 16; i++ {
		physical := physical_pages.take(1, 1)
		if physical == 0 { halt(c'user stack allocation') }
		runtime.fill(voidptr(physical), 0, 4096)
		if !user_space.map(0x5fff0000 + i * 4096, physical, true) { halt(c'user stack mapping') }
	}
	for i := u32(0); i < user_space.count; i++ {
		mapping := user_space.mappings[i]
		if mapping.virtual < 0x50000000 { cpu.publish_code(mapping.physical, 4096) }
	}
	user_space.activate()
	serial.text(c'Vinix: starting /bin/init in protected userspace\n')
	exception.enter_user(image.entry, 0x5ffffff0)
	halt(c'init returned')
}
