module termios

import proc

// mlibc programs share the kernel's own layout; Alpine binaries get Linux's.
pub fn user_size() u64 {
	if proc.current_thread().process.linux_abi {
		return linux_size
	}
	return sizeof(Termios)
}
