module kprint

import klock
import serial
import stivale2

__global (
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
		}

		kprint_lock.release()
	}
}

pub fn kprint(message charptr) {
	msglen := unsafe { u64(C.strlen(message)) }

	kprint_lock.acquire()

	$if !prod {
		unsafe {
			for i := 0; i < msglen; i++ {
				serial.out(message[i])
			}
		}
	}

	stivale2.terminal_print(message, msglen)

	kprint_lock.release()
}
