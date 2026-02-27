module kprint

import term
import aarch64.uart

pub fn syscall_kprint(_ voidptr, message charptr) {
	// TODO: full syscall path for ARM64
	uart.puts(message)
}

pub fn kwrite(message charptr, msglen u64) {
	kprint_lock.acquire()

	uart.write(message, msglen)
	term.print(message, msglen)

	kprint_lock.release()
}
