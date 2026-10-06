// SPDX-License-Identifier: ISC
@[has_globals; translated]
module ctlfixture

#include "ctl-native-abi.h"
@[typedef]
struct C.wifi_ctl_const_char {}

@[typedef]
struct C.wifi_ctl_const_termios {
	c_lflag usize
}

@[typedef]
struct C.wifi_ctl_const_timespec {
	tv_sec  isize
	tv_nsec isize
}

struct C.termios {
mut:
	c_lflag usize
}

struct C.timespec {
	tv_sec  isize
	tv_nsec isize
}

fn C.assert(bool)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strcmp(&char, &char) i32
fn C.strncmp(&char, &char, usize) i32
fn C.puts(&char) i32
fn C.atexit(fn ()) i32
fn C.test_program_main(i32, &&char) i32
fn C.wifi_ctl_verify_exit()

@[c_extern]
__global (
	C.ECHO              usize
	C.TCSANOW           i32
	C.BW_JOIN_SIZE      u32
	C.BW_STATUS_SIZE    u32
	C.BW_NETWORKS_SIZE  u32
	C.BW_IOCTL_STATUS   usize
	C.BW_IOCTL_NETWORKS usize
	C.BW_IOCTL_JOIN     usize
	C.BW_IOCTL_RADIO    usize
	C.BW_IOCTL_SCAN     usize
	C.BW_IOCTL_STOP     usize
	C.BW_IOCTL_UPLOAD   usize
	C.BW_IOCTL_BOOT     usize
)

__global (
	ctl_sleeps       u32
	ctl_queries      u32
	ctl_uploads      u32
	ctl_mode         &char
	ctl_join_request &u8
	tty_restored     i32
	input_at         u32
)

@[export:'wifi_ctl_verify_exit']
pub fn verify_exit() {
	unsafe { if C.strcmp(ctl_mode, c'load-bad') == 0 {
		C.assert(ctl_uploads == 0)
		C.puts(c'Wi-Fi pre-upload fixture: PASS')
	} }
}

fn le32(p &u8) u32 {
	unsafe { return u32(p[0]) | (u32(p[1]) << 8) | (u32(p[2]) << 16) | (u32(p[3]) << 24)
	 }
}

fn put32(p &u8, value u32) {
	unsafe { for i := u32(0); i < 4; i++ { p[i] = u8(value >> (i * 8)) }
	 }
}

@[export:'wifi_ctl_open_entry']
pub fn open_entry(path &C.wifi_ctl_const_char, flags i32) i32 {
	unsafe {
		_ = flags
		C.assert(C.strcmp(&char(path), c'/dev/wlan0') == 0 || C.strcmp(&char(path), c'/dev/tty') == 0)
		return if C.strcmp(&char(path), c'/dev/wlan0') == 0 { 100 } else { 101 }
	}
}

@[export:'test_close']
pub fn close_entry(fd i32) i32 {
	C.assert(fd == 100 || fd == 101)
	return 0
}

@[export:'test_read']
pub fn read_entry(fd i32, buffer voidptr, size usize) isize {
	unsafe {
		input := &u8(c'passphrase\n')
		C.assert(fd == 101 && size == 1)
		*(&u8(buffer)) = input[input_at]
		input_at++
		return 1
	}
}

@[export:'test_tcgetattr']
pub fn get_tty(fd i32, state &C.termios) i32 {
	unsafe {
		C.assert(fd == 101)
		C.memset(state, 0, sizeof(C.termios))
		state.c_lflag = C.ECHO
		return 0
	}
}

@[export:'test_tcsetattr']
pub fn set_tty(fd i32, action i32, state &C.wifi_ctl_const_termios) i32 {
	unsafe {
		C.assert(fd == 101 && action == C.TCSANOW)
		if state.c_lflag & C.ECHO != 0 { tty_restored++ }
		return 0
	}
}

@[export:'test_nanosleep']
pub fn sleep_entry(time &C.wifi_ctl_const_timespec, remaining &C.timespec) i32 {
	unsafe {
		_ = remaining
		C.assert(time.tv_sec == 0 && time.tv_nsec == 100000000)
		ctl_sleeps++
		return 0
	}
}

@[export:'wifi_ctl_ioctl_entry']
pub fn ioctl_entry(fd i32, request usize, out &u8) i32 {
	unsafe {
		C.assert(fd == 100)
		if request == C.BW_IOCTL_STATUS {
			if ctl_join_request != nil {
				for i := u32(0); i < u32(C.BW_JOIN_SIZE); i++ { C.assert(ctl_join_request[i] == 0) }
			}
			C.memset(out, 0, u32(C.BW_STATUS_SIZE))
			put32(out, if C.strcmp(ctl_mode, c'join-timeout') == 0 {
				u32(4)
			} else {
				if ctl_join_request != nil { u32(5) } else { u32(1) }
			})
			put32(out + 8, 3)
			return 0
		}
		if request == C.BW_IOCTL_NETWORKS {
			ctl_queries++
			C.memset(out, 0, u32(C.BW_NETWORKS_SIZE))
			put32(out, 1)
			put32(out + 4, 1)
			if C.strcmp(ctl_mode, c'scan') == 0 { put32(out + 8, 1) }
			out[16] = 4
			out[17] = 1
			out[18] = 6
			out[20] = 0xd6
			out[21] = 0xff
			C.memcpy(out + 32, c'test', 4)
			if C.strcmp(ctl_mode, c'invalid') == 0 { out[18] = 234 }
			return 0
		}
		if request == C.BW_IOCTL_JOIN {
			C.assert(le32(out) == 4 && le32(out + 4) == 10 && C.memcmp(out + 8, c'test', 4) == 0 && C.memcmp(out + 40, c'passphrase', 10) == 0)
			ctl_join_request = out
			return 0
		}
		if request == C.BW_IOCTL_RADIO {
			C.assert(le32(out) == if C.strcmp(ctl_mode, c'on') == 0 { u32(1) } else { u32(0) })
			return 0
		}
		if request == C.BW_IOCTL_SCAN || request == C.BW_IOCTL_STOP { return 0 }
		if request == C.BW_IOCTL_UPLOAD {
			ctl_uploads++
			part := le32(out)
			offset := le32(out + 8)
			length := le32(out + 12)
			C.assert(part < 4 && length <= 4096)
			for i := u32(0); i < length; i++ { C.assert(out[16 + i] == u8(part + 1)) }
			C.assert(offset % 4096 == 0)
			return 0
		}
		if request == C.BW_IOCTL_BOOT { return 0 }
		C.assert(false)
		return -1
	}
}

@[export:'wifi_fixture_main']
pub fn fixture_main(argc i32, argv &&char) i32 {
	unsafe {
		C.assert(argc == 2 || argc == 3)
		ctl_mode = argv[1]
		C.atexit(C.wifi_ctl_verify_exit)
		mut args := [&char(c'wifi-ctl'), ctl_mode, &char(c'test'), &char(nil)]!
		mut count := i32(2)
		if C.strcmp(ctl_mode, c'invalid') == 0 { args[1] = &char(c'networks') }
		if C.strncmp(ctl_mode, c'load', 4) == 0 {
			C.assert(argc == 3)
			args[1] = &char(c'load')
			args[2] = argv[2]
			count = 3
		}
		if C.strcmp(ctl_mode, c'join') == 0 || C.strcmp(ctl_mode, c'join-timeout') == 0 {
			args[1] = &char(c'join')
			count = 3
		}
		result := C.test_program_main(count, &&char(&args[0]))
		if C.strcmp(ctl_mode, c'invalid') == 0 {
			C.assert(result == 1)
		} else if C.strcmp(ctl_mode, c'join-timeout') == 0 {
			C.assert(result == 1 && ctl_sleeps == 310 && tty_restored == 1)
		} else {
			C.assert(result == 0)
		}
		if C.strcmp(ctl_mode, c'scan') == 0 { C.assert(ctl_queries == 161 && ctl_sleeps == 160) }
		if C.strcmp(ctl_mode, c'join') == 0 {
			C.assert(ctl_join_request != nil && tty_restored == 1)
		}
		C.assert(ctl_uploads == if C.strcmp(ctl_mode, c'load') == 0 { u32(5) } else { u32(0) })
		C.puts(c'Wi-Fi control fixture: PASS')
		return 0
	}
}
