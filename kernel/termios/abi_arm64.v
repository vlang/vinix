module termios

// Every aarch64 program is linked against musl, which passes its own larger
// struct straight to TCGETS and TCSETS and relies on the kernel touching only
// Linux's part of it.
pub fn user_size() u64 {
	return linux_size
}
