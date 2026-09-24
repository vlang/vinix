module kprint

import dev.serial
import term
import usercopy

const syscall_kprint_max = u64(4096)

pub fn syscall_kprint(_ voidptr, message charptr) {
	$if !prod {
		syscall_kprint_debug(message)
	}
}

fn syscall_kprint_debug(message charptr) {
	if message == unsafe { nil } {
		return
	}
	kprint_lock.acquire()
	defer { kprint_lock.release() }

	for i := u64(0); i < syscall_kprint_max; i++ {
		mut ch := u8(0)
		if !usercopy.copy_from_user(voidptr(&ch), u64(message) + i, 1) {
			return
		}
		if ch == 0 {
			serial.out(`\n`)
			return
		}
		serial.out(ch)
	}
}

fn serial_write(message charptr, msglen u64) {
	unsafe {
		for i := 0; i < msglen; i++ {
			serial.out(u8(message[i]))
		}
	}
}

pub fn kwrite(message charptr, msglen u64) {
	kprint_lock.acquire()

	$if !prod {
		serial_write(message, msglen)
	}

	term.print(message, msglen)

	kprint_lock.release()
}
