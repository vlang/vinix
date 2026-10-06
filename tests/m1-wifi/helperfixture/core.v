// SPDX-License-Identifier: ISC
// Independent native SDK boundary checks shared by frozen C and V helpers.
@[has_globals; translated]
module helperfixture

#include "helper-native-abi.h"
@[typedef]
struct C.FILE {}

struct C.termios {
mut:
	c_lflag usize
}

@[typedef]
struct C.wifi_helper_const_termios {}

fn C.assert(bool)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.vkw_terminal_save(i32) i32
fn C.vkw_terminal_hide(i32) i32
fn C.vkw_terminal_restore(i32) i32
fn C.vkw_errno() i32
fn C.vkw_set_errno(i32)
fn C.vkw_wipe_byte(voidptr)
fn C.vkw_stderr() &C.FILE
fn C.vkw_file_stat(&C.FILE, &i64, &i32) i32
fn C.tmpfile() &C.FILE
fn C.fileno(&C.FILE) i32
fn C.fwrite(voidptr, usize, usize, &C.FILE) usize
fn C.fflush(&C.FILE) i32
fn C.fclose(&C.FILE) i32
fn C.fopen(&char, &char) &C.FILE
fn C.close(i32) i32
fn C.puts(&char) i32
fn C.pause() i32

@[c_extern]
__global (
	C.stderr  &C.FILE
	C.stdout  &C.FILE
	C.ECHO    usize
	C.TCSANOW i32
	C.EBADF   i32
)

__global (
	tty_source   C.termios
	tty_received C.termios
	tty_calls    u32
)

@[export:'wifi_helper_tcgetattr']
pub fn get_terminal(fd i32, state &C.termios) i32 {
	unsafe {
		if fd != 123 { return -7 }
		C.memcpy(state, &tty_source, sizeof(C.termios))
		return 0
	}
}

@[export:'wifi_helper_tcsetattr']
pub fn set_terminal(fd i32, action i32, state &C.wifi_helper_const_termios) i32 {
	unsafe {
		C.assert(action == C.TCSANOW)
		if fd != 123 { return -8 }
		C.memcpy(&tty_received, state, sizeof(C.termios))
		tty_calls++
		return 0
	}
}

@[export:'main']
pub fn main_entry() i32 {
	unsafe {
		for pattern := u32(0); pattern < 256; pattern++ {
			C.memset(&tty_source, i32(pattern), sizeof(C.termios))
			tty_source.c_lflag = tty_source.c_lflag | C.ECHO
			C.assert(C.vkw_terminal_save(123) == 0)
			C.assert(C.vkw_terminal_save(-1) == -7)
			mut hidden := tty_source
			hidden.c_lflag = hidden.c_lflag & ~usize(C.ECHO)
			C.assert(C.vkw_terminal_hide(123) == 0)
			C.assert(C.memcmp(&tty_received, &hidden, sizeof(C.termios)) == 0)
			C.assert(C.vkw_terminal_hide(-1) == -8)
			C.assert(C.vkw_terminal_restore(123) == 0)
			C.assert(C.memcmp(&tty_received, &tty_source, sizeof(C.termios)) == 0)
			C.assert(C.vkw_terminal_restore(-1) == -8)
		}
		C.assert(tty_calls == 512)
		for value := i32(-16); value <= 256; value++ {
			C.vkw_set_errno(value)
			C.assert(C.vkw_errno() == value)
		}
		C.assert(usize(C.vkw_stderr()) == usize(C.stderr))
		mut bytes := [65]u8{}
		for index := usize(0); index < 65; index++ {
			C.memset(&bytes[0], 0xa5, sizeof(bytes))
			C.vkw_wipe_byte(&bytes[0] + index)
			for at := usize(0); at < 65; at++ {
				C.assert(bytes[at] == if at == index { u8(0) } else { u8(0xa5) })
			}
		}
		file := C.tmpfile()
		C.assert(file != nil)
		C.assert(C.fwrite(c'test', 1, 4, file) == 4 && C.fflush(file) == 0)
		mut size := i64(-123)
		mut regular := i32(-456)
		C.assert(C.vkw_file_stat(file, &size, &regular) == 0 && size == 4 && regular == 1)
		C.assert(C.close(C.fileno(file)) == 0)
		size = -123
		regular = -456
		C.assert(C.vkw_file_stat(file, &size, &regular) == -1)
		C.assert(C.vkw_errno() == C.EBADF && size == -123 && regular == -456)
		C.fclose(file)
		directory := C.fopen(c'/', c'r')
		C.assert(directory != nil)
		C.assert(C.vkw_file_stat(directory, &size, &regular) == 0 && regular == 0)
		C.assert(C.fclose(directory) == 0)
		C.puts(c'VINIX_WIFI_HELPERS_PASS')
		C.fflush(C.stdout)
		$if wifi_helper_guest ? {
			for { C.pause() }
		}
		return 0
	}
}
