// initramfs.v: USTAR initramfs driver.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module initramfs

import lib
import limine
import fs
import stat
import memory as _

struct USTARHeader {
	name       [100]u8
	mode       [8]u8
	uid        [8]u8
	gid        [8]u8
	size       [12]u8
	mtime      [12]u8
	checksum   [8]u8
	filetype   u8
	link_name  [100]u8
	signature  [6]u8
	version    [2]u8
	owner      [32]u8
	group      [32]u8
	device_maj [8]u8
	device_min [8]u8
	prefix     [155]u8
}

enum USTARFileType {
	regular_file = 0x30
	hard_link = 0x31
	sym_link = 0x32
	char_dev = 0x33
	block_dev = 0x34
	directory = 0x35
	fifo = 0x36
	gnu_long_path = 0x4c
}

fn octal_to_int(s string) u64 {
	mut ret := u64(0)
	for c in s {
		ret *= 8
		ret += u64(c) - 0x30
	}
	return ret
}

@[cinit]
@[_linker_section: '.requests']
__global (
	volatile module_req = limine.LimineModuleRequest{
		response: unsafe { nil }
	}
)

@[manualfree]
pub fn initialise() {
	if module_req.response == unsafe { nil } {
		panic('Modules bootloader response missing')
	}

	if module_req.response.module_count < 1 {
		panic('No initramfs')
	}

	mut modules := module_req.response.modules

	initramfs_begin := unsafe { modules[0].address }
	initramfs_size := unsafe { modules[0].size }

	println('initramfs: Address: 0x${voidptr(initramfs_begin):x}')
	println('initramfs: Size:    ${u32(initramfs_size):u}')

	print('initramfs: Unpacking...')

	mut name_override := ''
	mut current_header := &USTARHeader(unsafe { nil })
	unsafe {
		current_header = &USTARHeader(initramfs_begin)
	}
	for {
		sig := unsafe { tos(&current_header.signature[0], 5) }
		if sig != 'ustar' {
			break
		}

		name := if name_override == '' {
			unsafe { tos2(&current_header.name[0]) }
		} else {
			name_override
		}
		link_name := unsafe { tos2(&current_header.link_name[0]) }
		size := unsafe { octal_to_int(tos2(&current_header.size[0])) }
		mode := unsafe { octal_to_int(tos2(&current_header.mode[0])) }

		name_override = ''
		if name == './' {
			unsafe {
				goto next
			}
		}

		match unsafe { USTARFileType(current_header.filetype) } {
			.gnu_long_path {
				// limit for safety
				if size >= 65536 {
					panic('initramfs: long file name exceeds 65536 characters.')
				}

				name_override = unsafe { tos(voidptr(u64(current_header) + 512), int(size)) }
			}
			.directory {
				fs.create(vfs_root, name, u32(mode | stat.ifdir)) or {
					panic('initramfs: failed to create directory $name')
				}
			}
			.regular_file {
				new_node := fs.create(vfs_root, name, u32(mode | stat.ifreg)) or {
					panic('initramfs: failed to create file $name')
				}
				mut new_resource := new_node.resource
				buf := voidptr(u64(current_header) + 512)
				new_resource.write(0, buf, 0, size) or {
					panic('initramfs: failed to write file $name')
				}
			}
			.sym_link {
				fs.symlink(vfs_root, link_name, name) or {
					panic('initramfs: failed to create symlink $name')
				}
			}
			else {}
		}

		next:
		//memory.pmm_free(voidptr(u64(current_header) - higher_half), (u64(512) +
		//	lib.align_up(size, 512)) / page_size)

		current_header = &USTARHeader(usize(current_header) + usize(512) +
			usize(lib.align_up(size, 512)))
	}

	print('\ninitramfs: Done.\n')
}
