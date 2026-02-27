module kprint

import dev.serial

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
