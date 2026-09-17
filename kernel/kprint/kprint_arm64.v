module kprint

import term
import aarch64.uart
import usercopy

const syscall_kprint_max = u64(4096)

pub fn syscall_kprint(_ voidptr, message charptr) {
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
			uart.putc(u8(`\n`))
			return
		}
		uart.putc(ch)
	}
}

pub fn kwrite(message charptr, msglen u64) {
	kprint_lock.acquire()

	uart.write(message, msglen)
	term.print(message, msglen)

	kprint_lock.release()
}
