@[has_globals]
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
	regular_file  = 0x30
	hard_link     = 0x31
	sym_link      = 0x32
	char_dev      = 0x33
	block_dev     = 0x34
	directory     = 0x35
	fifo          = 0x36
	gnu_long_path = 0x4c
}

fn octal_to_int(s string) u64 {
	mut ret := u64(0)
	for c in s {
		if c < `0` || c > `7` {
			break
		}
		ret *= 8
		ret += u64(c) - 0x30
	}
	return ret
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile module_req = limine.LimineModuleRequest{
		response: unsafe { nil }
	}
)

fn C.aarch64__uart__putc(c u8)

fn uart_puts(s string) {
	for c in s {
		C.aarch64__uart__putc(c)
	}
}

fn uart_put_hex(v u64) {
	hex := '0123456789abcdef'
	for i := 60; i >= 0; i -= 4 {
		C.aarch64__uart__putc(hex[int((v >> u64(i)) & 0xf)])
	}
}

fn uart_put_dec(n u64) {
	if n == 0 {
		C.aarch64__uart__putc(`0`)
		return
	}
	mut buf := [20]u8{}
	mut i := 0
	mut v := n
	for v > 0 {
		buf[i] = u8(v % 10) + `0`
		v /= 10
		i++
	}
	for i > 0 {
		i--
		C.aarch64__uart__putc(buf[i])
	}
}

// Check USTAR signature without allocating memory
fn check_ustar(hdr &USTARHeader) bool {
	return unsafe {
		hdr.signature[0] == `u` && hdr.signature[1] == `s` &&
		hdr.signature[2] == `t` && hdr.signature[3] == `a` &&
		hdr.signature[4] == `r`
	}
}

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

	uart_puts('initramfs: Unpacking...\n')

	mut entry_count := u64(0)
	mut name_override := ''
	mut current_header := &USTARHeader(unsafe { nil })
	unsafe {
		current_header = &USTARHeader(initramfs_begin)
	}

	initramfs_end := u64(initramfs_begin) + initramfs_size

	for {
		// Bounds check
		if u64(current_header) >= initramfs_end {
			uart_puts('initramfs: past end of data\n')
			break
		}

		C.aarch64__uart__putc(`>`)

		// Check signature without V string allocation
		if !check_ustar(current_header) {
			uart_puts('initramfs: no ustar sig at 0x')
			uart_put_hex(u64(current_header))
			C.aarch64__uart__putc(`\n`)
			break
		}

		entry_count++
		C.aarch64__uart__putc(`+`)

		name := if name_override == '' {
			unsafe { tos2(&current_header.name[0]) }
		} else {
			name_override
		}

		// Prefix support for USTAR (paths >100 chars split into prefix + name)
		mut full_name := name
		prefix := unsafe { tos2(&current_header.prefix[0]) }
		if prefix.len > 0 && name_override == '' {
			full_name = '${prefix}/${name}'
		}

		link_name := unsafe { tos2(&current_header.link_name[0]) }
		size := unsafe { octal_to_int(tos2(&current_header.size[0])) }
		mode := unsafe { octal_to_int(tos2(&current_header.mode[0])) }

		// Debug: print first 20 and every 200th entry
		if entry_count <= 20 || entry_count % 200 == 0 {
			uart_puts(' [')
			uart_put_dec(entry_count)
			uart_puts('] ')
			uart_puts(full_name)
			uart_puts(' sz=')
			uart_put_dec(size)
			C.aarch64__uart__putc(`\n`)
		}

		name_override = ''
		if full_name == './' {
			unsafe {
				goto next
			}
		}

		match unsafe { USTARFileType(current_header.filetype) } {
			.gnu_long_path {
				if size >= 65536 {
					panic('initramfs: long file name exceeds 65536 characters.')
				}
				name_override = unsafe { tos(voidptr(u64(current_header) + 512), int(size)) }
			}
			.directory {
				fs.create(vfs_root, full_name, u32(mode | stat.ifdir)) or {}
			}
			.regular_file {
				new_node := fs.create(vfs_root, full_name, u32(mode | stat.ifreg)) or {
					uart_puts('initramfs: FAIL create ')
					uart_puts(full_name)
					C.aarch64__uart__putc(`\n`)
					panic('initramfs: failed to create file ${full_name}')
				}
				mut new_resource := new_node.resource
				buf := voidptr(u64(current_header) + 512)
				new_resource.write(0, buf, 0, size) or {
					panic('initramfs: failed to write file ${full_name}')
				}
			}
			.hard_link {
				fs.link(vfs_root, link_name, full_name) or {
					panic('initramfs: failed to create link ${full_name}')
				}
			}
			.sym_link {
				fs.symlink(vfs_root, link_name, full_name) or {
					panic('initramfs: failed to create symlink ${full_name}')
				}
			}
			else {}
		}

		C.aarch64__uart__putc(`!`)

		next:
		current_header = unsafe {
			&USTARHeader(usize(current_header) + usize(512) + usize(lib.align_up(size, 512)))
		}
	}

	uart_puts('initramfs: Done (')
	uart_put_dec(entry_count)
	uart_puts(' entries)\n')
}
