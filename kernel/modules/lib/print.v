module lib

import stivale2
import klock

__global (
	kprint_lock klock.Lock
)

pub fn syscall_kprint(_ voidptr, message charptr) {
	msglen := unsafe { C.strlen(message) }
	local_str := unsafe { C.malloc(msglen + 1) }
	unsafe { C.memcpy(local_str, message, msglen + 1) }

	kprint_lock.acquire()

	unsafe {
		for i := 0; i < msglen; i++ {
			asm volatile amd64 {
				out port, c
				;
				; Nd (0xe9) as port
				  a (local_str[i]) as c
				; memory
			}
		}
	}

	kprint_lock.release()

	unsafe { C.free(local_str) }
}

pub fn kprint(message string) {
	kprint_lock.acquire()

	for i := 0; i < message.len; i++ {
		asm volatile amd64 {
			out port, c
			; ; Nd (0xe9) as port
			  a (message[i]) as c
		}
	}

	stivale2.terminal_print(message)

	kprint_lock.release()
}

pub fn kprintc(message charptr) {
	kprint(unsafe { cstring_to_vstring(message) })
}

fn C.byteptr_vstring(byteptr) string
fn C.byteptr_vstring_with_len(byteptr, int) string
fn C.char_vstring(charptr) string
