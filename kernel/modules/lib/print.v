module lib

import stivale2
import klock

__global (
	kprint_lock klock.Lock
)

pub fn kprint(message string) {
	klock.acquire(kprint_lock)

	for i := 0; i < message.len; i++ {
		asm volatile amd64 {
			out port, c
			; ; Nd (0xe9) as port
			  a (message[i]) as c
		}
	}

	stivale2.terminal_print(message)

	klock.release(kprint_lock)
}

fn C.byteptr_vstring(byteptr) string
fn C.byteptr_vstring_with_len(byteptr, int) string
