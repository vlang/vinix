// SPDX-License-Identifier: BSD-2-Clause
// Native control runs both fixtures in children, retaining alarm(30) behavior.
@[translated]
module touchoracle

#include <touch-oracle-native-abi.h>

fn C.assert(bool)
fn C.fork() i32
fn C._exit(i32)
fn C.reap_ok(i32) i32
fn C.original_reap_ok(i32) i32
fn C.original_test_anonymous_first_touch() i32
fn C.test_anonymous_first_touch() i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

// Match the unchanged helper retained by the maintained feature driver.
@[export: 'reap_ok']
pub fn reap_input(child i32) i32 { return C.original_reap_ok(child) }

@[export: 'main']
pub fn main_entry() i32 {
	unsafe {
		mut console := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
		if console < 0 { console = C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY) }
		if console >= 0 {
			C.dup2(console, 1)
			C.dup2(console, 2)
			C.close(console)
		}
		for original in [true, false]! {
			child := C.fork()
			C.assert(child >= 0)
			if child == 0 {
				C._exit(if original { C.original_test_anonymous_first_touch() } else { C.test_anonymous_first_touch() })
			}
			C.assert(C.reap_ok(child) == 0)
		}
		C.puts(c'QEMU CORE TOUCH DIFFERENTIAL PASS: native C/V first-touch and thread barrier')
		C.fflush(nil)
		for { C.pause() }
	}
}
