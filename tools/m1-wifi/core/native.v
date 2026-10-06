// SPDX-License-Identifier: ISC
// Native SDK layouts retain terminal flags, FILE identity and errno storage.
@[translated]
module wificli

#include "wifi_v.h"
@[typedef]
struct C.FILE {}

struct C.termios {
mut:
	c_lflag usize
}

struct C.stat {
	st_size i64
	st_mode u32
}

struct C.vkw_volatile_byte_view {
mut:
	value u8
}

fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.vkw_native_errno() &i32
fn C.fileno(&C.FILE) i32
fn C.fstat(i32, &C.stat) i32
fn C.S_ISREG(u32) i32

@[c_extern]
__global (
	C.stderr  &C.FILE
	C.ECHO    usize
	C.TCSANOW i32
)

__global saved_terminal C.termios

@[export:'vkw_terminal_save']
pub fn terminal_save(fd i32) i32 { return unsafe { C.tcgetattr(fd, &saved_terminal) } }

@[export:'vkw_terminal_hide']
pub fn terminal_hide(fd i32) i32 {
	unsafe {
		mut state := saved_terminal
		state.c_lflag = state.c_lflag & ~usize(C.ECHO)
		return C.tcsetattr(fd, C.TCSANOW, &state)
	}
}

@[export:'vkw_terminal_restore']
pub fn terminal_restore(fd i32) i32 {
	return unsafe { C.tcsetattr(fd, C.TCSANOW, &saved_terminal) }
}

@[export:'vkw_errno']
pub fn error_number() i32 { return unsafe { *C.vkw_native_errno() } }

@[export:'vkw_set_errno']
pub fn set_error_number(value i32) {
	unsafe { *C.vkw_native_errno() = value }
}

@[export:'vkw_wipe_byte']
pub fn wipe_byte(pointer voidptr) {
	unsafe { (&C.vkw_volatile_byte_view(pointer)).value = 0 }
}

@[export:'vkw_stderr']
pub fn stderr_pointer() &C.FILE { return C.stderr }

@[export:'vkw_file_stat']
pub fn file_stat(file &C.FILE, size &i64, regular &i32) i32 {
	unsafe {
		mut st := C.stat{}
		rc := C.fstat(C.fileno(file), &st)
		if rc == 0 {
			*size = st.st_size
			*regular = C.S_ISREG(st.st_mode)
		}
		return rc
	}
}
