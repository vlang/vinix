// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.posix_openpt(i32) i32
fn C.grantpt(i32) i32
fn C.unlockpt(i32) i32
fn C.ptsname(i32) &char

fn terminal_test_pair() (i32, i32) {
	// musl ptsname() returns shared storage. Hold the native guard until open
	// has consumed that name, then use independent descriptors in each worker.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
	assert master >= 0
	assert C.grantpt(master) == 0 && C.unlockpt(master) == 0
	slave := C.open(C.ptsname(master), C.O_RDWR | C.O_NOCTTY, i32(0))
	assert slave >= 0
	return master, slave
}

fn terminal_test_attributes(fd i32) DarwinTerminal {
	buffer := unsafe { &u8(C.__builtin_alloca(88)) }
	C.memset(buffer, 0xaa, 88)
	darwin_set_errno(177)
	value := unsafe { &DarwinTerminal(&buffer[8]) }
	assert darwin_tcgetattr(fd, value) == 0 && unsafe { *C.ios_errno_address() } == 177
	for index in 0 .. 8 {
		assert unsafe { buffer[index] == 0xaa && buffer[80 + index] == 0xaa }
	}
	$if macos {
		native := unsafe { &u8(C.__builtin_alloca(88)) }
		C.memset(native, 0xaa, 88)
		assert C.tcgetattr(fd, unsafe { &C.termios(&native[8]) }) == 0
		assert C.memcmp(buffer, native, 88) == 0
	}
	return unsafe { *value }
}

fn terminal_test_worker() {
	master, slave := terminal_test_pair()
	defer {
		C.close(slave)
		C.close(master)
	}
	saved := terminal_test_attributes(slave)
	mut value := saved
	value.input ^= 0xc00 // IXOFF and IXANY have different native bit positions.
	value.output |= 4 // Native tab expansion is an encoded field on Linux.
	value.characters[8] = 5
	value.characters[9] = 6
	value.characters[0] = 7
	value.characters[16] = 0
	value.characters[17] = 3
	assert darwin_tcsetattr(slave, 0, unsafe { &value }) == 0
	flags := terminal_test_attributes(slave)
	assert flags.input == value.input && flags.output == value.output
	assert flags.characters[8] == 5 && flags.characters[9] == 6 && flags.characters[0] == 7
	assert flags.characters[16] == 0 && flags.characters[17] == 3
	mut mapped := C.termios{}
	assert C.tcgetattr(slave, unsafe { &mapped }) == 0
	assert (mapped.c_iflag & u64(C.IXOFF) != 0) == (value.input & 0x400 != 0)
	assert (mapped.c_iflag & u64(C.IXANY) != 0) == (value.input & 0x800 != 0)
	assert mapped.c_cc[C.VINTR] == 5 && mapped.c_cc[C.VQUIT] == 6 && mapped.c_cc[C.VEOF] == 7
	assert mapped.c_cc[C.VMIN] == 0 && mapped.c_cc[C.VTIME] == 3
	assert darwin_tcsetattr(slave, 0, unsafe { &saved }) == 0
	value = saved
	value.local &= ~u64(8)
	for action in [i32(0), 1, 2, 16, 17, 18] {
		darwin_set_errno(177)
		assert darwin_tcsetattr(slave, action, unsafe { &value }) == 0
		assert unsafe { *C.ios_errno_address() } == 177
		after := terminal_test_attributes(slave)
		assert after.local & 8 == 0 && after.input == saved.input && after.output == saved.output
		if after.control != saved.control || after.input_speed != saved.input_speed || after.output_speed != saved.output_speed {
			eprintln('IOS-TERMINAL: action=${action} control=${saved.control:x}->${after.control:x} input=${saved.input_speed}->${after.input_speed} output=${saved.output_speed}->${after.output_speed}')
		}
		assert after.control == saved.control && after.input_speed == saved.input_speed && after.output_speed == saved.output_speed
		assert C.memcmp(unsafe { &value }, unsafe { &after }, 72) == 0
		assert C.memcmp(unsafe { &saved }, unsafe { &value }, 24) == 0
	}
	// A real PTY must stop echoing bytes while still delivering its input.
	assert C.write(master, c'Q\n', 2) == 2
	mut readback := [16]u8{}
	assert C.read(slave, unsafe { &readback[0] }, 16) == 2
	assert readback[0] == `Q` && readback[1] == `\n`
	assert C.fcntl(master, C.F_SETFL, usize(C.O_NONBLOCK)) == 0
	assert C.read(master, unsafe { &readback[0] }, 16) == -1
	assert unsafe { *C.ios_errno_address() } == C.EAGAIN
	assert darwin_tcsetattr(slave, 0, unsafe { &saved }) == 0
	value = saved
	value.control |= 1 // CIGNORE is the same hardware-preserving request.
	value.input_speed = 115200
	value.output_speed = 115200
	value.local &= ~u64(8)
	assert darwin_tcsetattr(slave, 0, unsafe { &value }) == 0
	ignored := terminal_test_attributes(slave)
	assert ignored.control == saved.control && ignored.input_speed == saved.input_speed && ignored.output_speed == saved.output_speed
	assert ignored.local & 8 == 0
	assert darwin_tcsetattr(slave, 0, unsafe { &saved }) == 0
	assert C.write(master, c'R\n', 2) == 2
	assert C.read(slave, unsafe { &readback[0] }, 16) == 2
	assert C.read(master, unsafe { &readback[0] }, 16) > 0
	assert readback[0] == `R`
	// Software-only updates preserve hardware control and baud values.
	value = saved
	value.local &= ~u64(8)
	value.input_speed = 115200
	value.output_speed = 115200
	value.control ^= 0x4000
	assert darwin_tcsetattr(slave, 16, unsafe { &value }) == 0
	soft := terminal_test_attributes(slave)
	assert soft.control == saved.control && soft.input_speed == saved.input_speed && soft.output_speed == saved.output_speed
	assert soft.local & 8 == 0
	assert darwin_tcsetattr(slave, 0, unsafe { &saved }) == 0
	// Changes to ordinary rates reach the native terminal, and input zero means
	// use the output rate. Read back through both APIs rather than assuming it.
	value = saved
	value.input_speed = 0
	value.output_speed = 19200
	assert darwin_tcsetattr(slave, 0, unsafe { &value }) == 0
	speed := terminal_test_attributes(slave)
	assert speed.input_speed == 19200 && speed.output_speed == 19200
	mut native := C.termios{}
	assert C.tcgetattr(slave, unsafe { &native }) == 0
	assert C.cfgetospeed(unsafe { &native }) == (terminal_speed(19200, true) or { panic('native baud') })
	value.input_speed = 9600
	assert darwin_tcsetattr(slave, 0, unsafe { &value }) == 0
	separate := terminal_test_attributes(slave)
	assert separate.input_speed == 9600 && separate.output_speed == 19200
	assert darwin_tcsetattr(slave, 0, unsafe { &saved }) == 0
	for _ in 0 .. 32 {
		value = saved
		value.local &= ~u64(8)
		assert darwin_tcsetattr(slave, 0, unsafe { &value }) == 0
		assert terminal_test_attributes(slave).local & 8 == 0
		assert darwin_tcsetattr(slave, 0, unsafe { &saved }) == 0
		assert terminal_test_attributes(slave).local == saved.local
	}
	$if linux {
		// Unknown native state must leave the entire Darwin buffer untouched.
		assert C.tcgetattr(slave, unsafe { &native }) == 0
		native_saved := native
		native.c_oflag |= u64(C.OLCUC)
		assert C.tcsetattr(slave, C.TCSANOW, unsafe { &native }) == 0
		guard := unsafe { &u8(C.__builtin_alloca(88)) }
		C.memset(guard, 0xaa, 88)
		assert darwin_tcgetattr(slave, unsafe { &DarwinTerminal(&guard[8]) }) == -1
		assert unsafe { *C.ios_errno_address() } == 45
		for index in 0 .. 88 {
			assert unsafe { guard[index] } == 0xaa
		}
		assert C.tcsetattr(slave, C.TCSANOW, unsafe { &native_saved }) == 0
		value = saved
		value.local |= 0x200 // ALTWERASE has no native equivalent.
		assert darwin_tcsetattr(slave, 0, unsafe { &value }) == -1
		assert unsafe { *C.ios_errno_address() } == 45
		assert terminal_test_attributes(slave).local == saved.local
		value = saved
		value.characters[8] = 0 // An enabled NUL VINTR cannot be represented.
		assert darwin_tcsetattr(slave, 0, unsafe { &value }) == -1
		assert unsafe { *C.ios_errno_address() } == 45
		value = saved
		value.input_speed = 7200
		value.output_speed = 7200
		assert darwin_tcsetattr(slave, 0, unsafe { &value }) == -1
		assert unsafe { *C.ios_errno_address() } == 22
	}
}

fn terminal_test_errors() {
	mut descriptors := [2]i32{}
	assert C.pipe(unsafe { &descriptors[0] }) == 0
	defer {
		C.close(descriptors[0])
		C.close(descriptors[1])
	}
	for fd in [i32(-1), descriptors[0]] {
		buffer := unsafe { &u8(C.__builtin_alloca(88)) }
		C.memset(buffer, 0xaa, 88)
		value := unsafe { &DarwinTerminal(&buffer[8]) }
		assert darwin_tcgetattr(fd, value) == -1
		assert unsafe { *C.ios_errno_address() } == if fd == -1 { 9 } else { 25 }
		for index in 0 .. 88 {
			assert unsafe { buffer[index] } == 0xaa
		}
		assert darwin_tcsetattr(fd, 0, value) == -1
		assert unsafe { *C.ios_errno_address() } == if fd == -1 { 9 } else { 25 }
		for action in [i32(3), -1, 4, 0x20] {
			assert darwin_tcsetattr(fd, action, value) == -1
			assert unsafe { *C.ios_errno_address() } == 22
		}
	}
	master, slave := terminal_test_pair()
	defer {
		C.close(slave)
		C.close(master)
	}
	assert darwin_tcgetattr(slave, unsafe { nil }) == -1 && unsafe { *C.ios_errno_address() } == 14
	assert darwin_tcsetattr(slave, 0, unsafe { nil }) == -1 && unsafe { *C.ios_errno_address() } == 14
}

fn test_darwin_terminal_attributes() {
	assert sizeof(DarwinTerminal) == 72
	terminal_test_errors()
	for _ in 0 .. 2 {
		system_data_start()!
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn terminal_test_worker() }
		workers.wait()
		system_data_stop()
	}
	assert (terminal_symbol('_tcgetattr') or { u64(0) }) != 0
	assert (terminal_symbol('_tcsetattr') or { u64(0) }) != 0
	println('IOS-TERMINAL: guarded 72-byte ABI, real PTY echo, baud/soft updates, errors, four workers and two teardowns')
}
