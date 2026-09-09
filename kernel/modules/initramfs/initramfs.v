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

// USTAR fields fill their complete fixed-width array when a value is exactly
// as long as the field, in which case there is no trailing NUL. tos2() would
// then continue into the following field (a 100-byte name became
// "name0000644" by reading its mode), so every header string must be bounded.
fn ustar_field_string(field &u8, capacity int) string {
	mut length := 0
	unsafe {
		for length < capacity && field[length] != 0 {
			length++
		}
		return tos(field, length)
	}
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile module_req = limine.LimineModuleRequest{
		response: unsafe { nil }
	}
)

fn uart_puts(s string) {
	for c in s {
		uart_putc(c)
	}
}

fn uart_put_hex(v u64) {
	hex := '0123456789abcdef'
	for i := 60; i >= 0; i -= 4 {
		uart_putc(hex[int((v >> u64(i)) & 0xf)])
	}
}

fn uart_put_dec(n u64) {
	if n == 0 {
		uart_putc(`0`)
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
		uart_putc(buf[i])
	}
}

// Check USTAR signature without allocating memory
fn check_ustar(hdr &USTARHeader) bool {
	return unsafe {
		hdr.signature[0] == `u` && hdr.signature[1] == `s` && hdr.signature[2] == `t`
			&& hdr.signature[3] == `a` && hdr.signature[4] == `r`
	}
}

@[manualfree]
fn unpack(initramfs_begin voidptr, initramfs_size u64, module_index u64) {
	println('initramfs: Module:  ${module_index + 1}')
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

		uart_putc(`>`)

		// Check signature without V string allocation
		if !check_ustar(current_header) {
			uart_puts('initramfs: no ustar sig at 0x')
			uart_put_hex(u64(current_header))
			uart_putc(`\n`)
			break
		}

		entry_count++
		uart_putc(`+`)

		name := if name_override == '' {
			ustar_field_string(&current_header.name[0], current_header.name.len)
		} else {
			name_override
		}

		// Prefix support for USTAR (paths >100 chars split into prefix + name)
		mut full_name := name
		prefix := ustar_field_string(&current_header.prefix[0], current_header.prefix.len)
		if prefix.len > 0 && name_override == '' {
			full_name = '${prefix}/${name}'
		}

		link_name := ustar_field_string(&current_header.link_name[0], current_header.link_name.len)
		size := octal_to_int(ustar_field_string(&current_header.size[0], current_header.size.len))
		mode := octal_to_int(ustar_field_string(&current_header.mode[0], current_header.mode.len))

		// Debug: print first 20 and every 200th entry
		if entry_count <= 20 || entry_count % 200 == 0 {
			uart_puts(' [')
			uart_put_dec(entry_count)
			uart_puts('] ')
			uart_puts(full_name)
			uart_puts(' sz=')
			uart_put_dec(size)
			uart_putc(`\n`)
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
				// A name that is already there is not a failure. An archive
				// built by appending one staging tree to another repeats
				// whatever both supply, and the last copy is the one meant to
				// win — the same as unpacking the tar with any other tool.
				// This used to take the whole kernel down before init ran.
				mut new_node := fs.create(vfs_root, full_name, u32(mode | stat.ifreg)) or {
					fs.get_node(vfs_root, full_name, false) or {
						uart_puts('initramfs: FAIL create ')
						uart_puts(full_name)
						uart_putc(`\n`)
						panic('initramfs: failed to create file ${full_name}')
					}
				}
				mut new_resource := new_node.resource
				// Overwrite only what is already a plain file. A name that
				// arrives as a file over something that is not one — a
				// directory the earlier tree put there — is left alone.
				if stat.isreg(new_resource.stat.mode) {
					buf := voidptr(u64(current_header) + 512)
					// Limine module memory remains reserved and mapped after
					// boot.  Let tmpfs read straight from it until a process
					// modifies the file, instead of duplicating the entire root
					// filesystem while the archive is still resident.
					if !fs.tmpfs_borrow_storage(mut new_resource, buf, size) {
						// Keep the generic path for a regular file supplied by some
						// other root filesystem implementation.
						new_resource.grow(unsafe { nil }, size) or {}
						new_resource.write(0, buf, 0, size) or {
							panic('initramfs: failed to write file ${full_name}')
						}
					}
				}
			}
			.hard_link {
				fs.link(vfs_root, link_name, full_name) or {}
			}
			.sym_link {
				fs.symlink(vfs_root, link_name, full_name) or {}
			}
			else {}
		}

		uart_putc(`!`)

		next:
		current_header = unsafe {
			&USTARHeader(usize(current_header) + usize(512) + usize(lib.align_up(size, 512)))
		}
	}

	uart_puts('initramfs: Done (')
	uart_put_dec(entry_count)
	uart_puts(' entries)\n')
}

@[manualfree]
pub fn initialise() {
	if module_req.response == unsafe { nil } {
		panic('Modules bootloader response missing')
	}

	if module_req.response.module_count < 1 {
		panic('No initramfs')
	}

	modules := module_req.response.modules
	for module_index := u64(0); module_index < module_req.response.module_count; module_index++ {
		archive_module := unsafe { modules[module_index] }
		if archive_module == unsafe { nil } || archive_module.size < 512 {
			panic('Invalid initramfs module')
		}
		unpack(archive_module.address, archive_module.size, module_index)
	}
}
