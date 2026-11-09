// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

__global line [256]u8
__global response [1024]u8
__global boundary_buffer [8192]u8

fn C.vinix_user_syscall(number u32, a u32, b u32, c u32) i32

asm ppc raw {
	".pushsection .text.vinix_user_syscall,\"ax\"\n.balign 4\n"
	".globl vinix_user_syscall\nvinix_user_syscall:\n"
	"mr 0,3\nmr 3,4\nmr 4,5\nmr 5,6\nsc\nbns 1f\nneg 3,3\n1: blr\n.popsection\n"
}

fn length(text &char) u32 {
	mut size := u32(0)
	unsafe { for text[size] != 0 { size++ }
	 }
	return size
}

fn print_text(text &char) {
	C.vinix_user_syscall(4, 1, u32(text), length(text))
}

fn number(value u32) {
	mut digits := [11]u8{}
	mut at := 10
	mut current := value
	unsafe {
		for {
			at--
			(&u8(&digits[0]))[at] = `0` + u8(current % 10)
			current /= 10
			if current == 0 { break }
		}
		C.vinix_user_syscall(4, 1, u32(&digits[at]), u32(10 - at))
	}
}

fn same(left &u8, right &char) bool {
	unsafe {
		mut i := u32(0)
		for left[i] != 0 && right[i] != 0 {
			if left[i] != u8(right[i]) { return false }
			i++
		}
		return left[i] == 0 && right[i] == 0
	}
}

fn open(path &char) i32 { return C.vinix_user_syscall(5, u32(path), 0, 0) }

fn close(fd i32) { C.vinix_user_syscall(6, u32(fd), 0, 0) }

fn cat(path &char) {
	fd := open(path)
	if fd < 0 {
		print_text(c'cat: cannot open file\n')
		return
	}
	for {
		count := C.vinix_user_syscall(3, u32(fd), u32(unsafe { &response[0] }), 1024)
		if count <= 0 { break }
		C.vinix_user_syscall(4, 1, u32(unsafe { &response[0] }), u32(count))
	}
	close(fd)
}

fn ls(path &char) {
	fd := open(path)
	if fd < 0 {
		print_text(c'ls: cannot open directory\n')
		return
	}
	for {
		count := C.vinix_user_syscall(141, u32(fd), u32(unsafe { &response[0] }), 1024)
		if count < 0 {
			print_text(c'ls: not a directory\n')
			break
		}
		if count == 0 { break }
		unsafe {
			mut at := 0
			for at + 12 <= count {
				data := &u8(&response[0])
				size := int(data[at + 8]) * 256 + int(data[at + 9])
				if size < 12 || at + size > count { break }
				print_text(&char(&data[at + 10]))
				if data[at + size - 1] == 4 { print_text(c'/') }
				print_text(c'\n')
				at += size
			}
		}
	}
	close(fd)
}

fn word(at u32) u32 {
	unsafe {
		data := &u8(&response[0])
		return u32(data[at]) << 24 | u32(data[at + 1]) << 16 | u32(data[at + 2]) << 8 | u32(data[at + 3])
	}
}

fn boundary_check() {
	if C.vinix_user_syscall(4, 1, 0x02000000, 16) != -14
		|| C.vinix_user_syscall(3, 0, 0x40000000, 1) != -14
		|| C.vinix_user_syscall(4, 1, 0x5fffffff, 2) != -14
		|| C.vinix_user_syscall(9999, 0, 0, 0) != -38
		|| C.vinix_user_syscall(0x7f00, 0, 0, 0) != -38
		|| C.vinix_user_syscall(0x7f02, 0, 0, 0) != -38
		|| C.vinix_user_syscall(5, 0x02000000, 0, 0) != -14
		|| C.vinix_user_syscall(116, 0x40000000, 0, 0) != -14
		|| C.vinix_user_syscall(122, 0x5fffffff, 0, 0) != -14
		|| C.vinix_user_syscall(6, 16, 0, 0) != -9
		|| C.vinix_user_syscall(4, 3, 0, 0) != -9
		|| open(c'/missing') != -2 { failed_check() }
	// Exhaust all file slots and check that closing them restores capacity.
	for fd in 3 .. 64 { if open(c'/etc/motd') != fd { failed_check() } }
	if open(c'/etc/motd') != -24 { failed_check() }
	for fd in 3 .. 64 { close(fd) }
	if C.vinix_user_syscall(6, 3, 0, 0) != -9 { failed_check() }
	fd := open(c'/etc/motd')
	// Deliberately span two virtual pages; physical frames need not be adjacent.
	base := u32(unsafe { &boundary_buffer[0] })
	crossing := ((base + 4097) & ~u32(4095)) - 2
	if fd != 3 || C.vinix_user_syscall(3, u32(fd), crossing, 5) != 5 { failed_check() }
	unsafe {
		bytes := &u8(crossing)
		if bytes[0] != `V` || bytes[1] != `i` || bytes[2] != `n` || bytes[3] != `i` || bytes[4] != `x` {
			failed_check()
		}
	}
	close(fd)
	dir := open(c'/')
	if dir != 3 || C.vinix_user_syscall(141, u32(dir), base, 1) != -22
		|| C.vinix_user_syscall(141, u32(dir), 0x40000000, 1024) != -14
		|| C.vinix_user_syscall(141, u32(dir), base, 1024) <= 0 { failed_check() }
	close(dir)
	print_text(c'VINIX-PPC: PASS userspace syscall boundary\n')
}

fn failed_check() {
	print_text(c'VINIX-PPC: FAIL userspace syscall boundary\n')
	C.vinix_user_syscall(1, 1, 0, 0)
	for {}
}

@[export: 'vinix_user_init']
fn start() {
	if C.vinix_user_syscall(20, 0, 0, 0) == 1 { boundary_check() }
	cat(c'/etc/motd')
	print_text(c'Type help for commands.\n')
	for {
		print_text(c'vinix$ ')
		mut used := 0
		unsafe {
			mut input := &u8(&line[0])
			for {
				mut byte := u8(0)
				if C.vinix_user_syscall(3, 0, u32(&byte), 1) != 1 { continue }
				if byte == `\r` || byte == `\n` {
					print_text(c'\n')
					break
				}
				if byte == 8 || byte == 127 {
					if used > 0 {
						used--
						print_text(c'\b \b')
					}
					continue
				}
				if byte >= 32 && byte <= 126 && used < 255 {
					input[used] = byte
					used++
					C.vinix_user_syscall(4, 1, u32(&byte), 1)
				}
			}
			input[used] = 0
			mut split := 0
			for split < used && input[split] != ` ` { split++ }
			mut argument := split
			if split < used {
				input[split] = 0
				argument++
				for argument < used && input[argument] == ` ` { argument++ }
			}
			arg := &char(&input[argument])
			if same(input, c'help') {
				print_text(c'help  ls [path]  cat path  pwd  ps  uname  mem  net  ping [IPv4]  tone  fbtest  pointertest  echo text  exit\n')
			} else if same(input, c'ls') {
				ls(if argument < used { arg } else { c'/' })
			} else if same(input, c'cat') {
				cat(arg)
			} else if same(input, c'pwd') {
				print_text(c'/\n')
			} else if same(input, c'echo') {
				print_text(arg)
				print_text(c'\n')
			} else if same(input, c'ps') {
				print_text(c'PID  COMMAND\n')
				number(u32(C.vinix_user_syscall(20, 0, 0, 0)))
				print_text(c'    init (shell)\n')
			} else if same(input, c'uname') {
				if C.vinix_user_syscall(122, u32(&response[0]), 0, 0) == 0 {
					print_text(&char(&response[0]))
					print_text(c' ')
					print_text(&char(&response[130]))
					print_text(c' ')
					print_text(&char(&response[260]))
					print_text(c'\n')
				}
			} else if same(input, c'mem') {
				if C.vinix_user_syscall(116, u32(&response[0]), 0, 0) == 0 {
					print_text(c'Managed KiB: ')
					number(word(16) / 1024)
					print_text(c' Free KiB: ')
					number(word(20) / 1024)
					print_text(c' Uptime seconds: ')
					number(word(0))
					print_text(c'\n')
				}
			} else if same(input, c'net') {
				network_command(arg, false)
			} else if same(input, c'ping') {
				network_command(arg, true)
			} else if same(input, c'tone') {
				tone()
			} else if same(input, c'fbtest') {
				framebuffer_test()
			} else if same(input, c'pointertest') {
				pointer_test()
			} else if same(input, c'exit') {
				C.vinix_user_syscall(1, 0, 0, 0)
			} else if used != 0 {
				print_text(c'Unknown command. Type help.\n')
			}
		}
	}
}

@[export: 'v_fixed_index']
fn checked_index(index i64, size int) int {
	if index < 0 || index >= size {
		C.vinix_user_syscall(1, 2, 0, 0)
		for {}
	}
	return int(index)
}
