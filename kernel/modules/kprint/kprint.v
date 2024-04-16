// kprint.v: kprint debug syscall.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module kprint

import klock
import dev.serial
import term

__global (
	printf_lock klock.Lock
	kprint_lock klock.Lock
)

pub fn syscall_kprint(_ voidptr, message charptr) {
	$if !prod {
		msglen := unsafe { u64(C.strlen(message)) }

		kprint_lock.acquire()

		unsafe {
			for i := 0; i < msglen; i++ {
				serial.out(message[i])
			}
			serial.out(`\n`)
		}
		kprint_lock.release()
	}
}

pub fn kwrite(message charptr, msglen u64) {
	kprint_lock.acquire()

	$if !prod {
		unsafe {
			for i := 0; i < msglen; i++ {
				serial.out(message[i])
			}
		}
	}

	term.print(message, msglen)

	kprint_lock.release()
}

fn C.byteptr_vstring(byteptr) string
fn C.byteptr_vstring_with_len(byteptr, int) string
fn C.char_vstring(charptr) string
