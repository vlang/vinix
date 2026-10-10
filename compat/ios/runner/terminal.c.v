// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <termios.h>

struct C.termios {
mut:
	c_iflag u64
	c_oflag u64
	c_cflag u64
	c_lflag u64
	c_cc    [32]u8
}

fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.cfgetispeed(&C.termios) u64
fn C.cfgetospeed(&C.termios) u64
fn C.cfsetispeed(&C.termios, u64) i32
fn C.cfsetospeed(&C.termios, u64) i32

struct DarwinTerminal {
mut:
	input        u64
	output       u64
	control      u64
	local        u64
	characters   [20]u8
	padding      u32
	input_speed  u64
	output_speed u64
}

struct TerminalFlag {
	darwin u64
	native u64
}

const terminal_input_flags = [
	TerminalFlag{0x1, u64(C.IGNBRK)},
	TerminalFlag{0x2, u64(C.BRKINT)},
	TerminalFlag{0x4, u64(C.IGNPAR)},
	TerminalFlag{0x8, u64(C.PARMRK)},
	TerminalFlag{0x10, u64(C.INPCK)},
	TerminalFlag{0x20, u64(C.ISTRIP)},
	TerminalFlag{0x40, u64(C.INLCR)},
	TerminalFlag{0x80, u64(C.IGNCR)},
	TerminalFlag{0x100, u64(C.ICRNL)},
	TerminalFlag{0x200, u64(C.IXON)},
	TerminalFlag{0x400, u64(C.IXOFF)},
	TerminalFlag{0x800, u64(C.IXANY)},
	TerminalFlag{0x2000, u64(C.IMAXBEL)},
	TerminalFlag{0x4000, u64(C.IUTF8)},
]!

const terminal_output_flags = [
	TerminalFlag{0x1, u64(C.OPOST)},
	TerminalFlag{0x2, u64(C.ONLCR)},
	TerminalFlag{0x10, u64(C.OCRNL)},
	TerminalFlag{0x20, u64(C.ONOCR)},
	TerminalFlag{0x40, u64(C.ONLRET)},
]!

const terminal_control_flags = [
	TerminalFlag{0x100, u64(C.CS6)},
	TerminalFlag{0x200, u64(C.CS7)},
	TerminalFlag{0x400, u64(C.CSTOPB)},
	TerminalFlag{0x800, u64(C.CREAD)},
	TerminalFlag{0x1000, u64(C.PARENB)},
	TerminalFlag{0x2000, u64(C.PARODD)},
	TerminalFlag{0x4000, u64(C.HUPCL)},
	TerminalFlag{0x8000, u64(C.CLOCAL)},
	TerminalFlag{0x30000, u64(C.CRTSCTS)},
]!

const terminal_local_flags = [
	TerminalFlag{0x1, u64(C.ECHOKE)},
	TerminalFlag{0x2, u64(C.ECHOE)},
	TerminalFlag{0x4, u64(C.ECHOK)},
	TerminalFlag{0x8, u64(C.ECHO)},
	TerminalFlag{0x10, u64(C.ECHONL)},
	TerminalFlag{0x20, u64(C.ECHOPRT)},
	TerminalFlag{0x40, u64(C.ECHOCTL)},
	TerminalFlag{0x80, u64(C.ISIG)},
	TerminalFlag{0x100, u64(C.ICANON)},
	TerminalFlag{0x400, u64(C.IEXTEN)},
	TerminalFlag{0x800, u64(C.EXTPROC)},
	TerminalFlag{0x400000, u64(C.TOSTOP)},
	TerminalFlag{0x800000, u64(C.FLUSHO)},
	TerminalFlag{0x20000000, u64(C.PENDIN)},
	TerminalFlag{0x80000000, u64(C.NOFLSH)},
]!

const terminal_character_indices = [
	i32(C.VEOF),
	C.VEOL,
	C.VEOL2,
	C.VERASE,
	C.VWERASE,
	C.VKILL,
	C.VREPRINT,
	-1,
	C.VINTR,
	C.VQUIT,
	C.VSUSP,
	-1,
	C.VSTART,
	C.VSTOP,
	C.VLNEXT,
	C.VDISCARD,
	C.VMIN,
	C.VTIME,
	-1,
	-1,
]!

fn terminal_flags(value u64, pairs &TerminalFlag, count int, to_native bool) ?u64 {
	mut remaining := value
	mut result := u64(0)
	for index in 0 .. count {
		pair := unsafe { pairs[index] }
		from := if to_native { pair.darwin } else { pair.native }
		to := if to_native { pair.native } else { pair.darwin }
		if remaining & from == from {
			remaining &= ~from
			result |= to
		}
	}
	if remaining != 0 { return none }
	return result
}

fn terminal_speed(value u64, to_native bool) ?u64 {
	for pair in [
		TerminalFlag{0, u64(C.B0)},
		TerminalFlag{50, u64(C.B50)},
		TerminalFlag{75, u64(C.B75)},
		TerminalFlag{110, u64(C.B110)},
		TerminalFlag{134, u64(C.B134)},
		TerminalFlag{150, u64(C.B150)},
		TerminalFlag{200, u64(C.B200)},
		TerminalFlag{300, u64(C.B300)},
		TerminalFlag{600, u64(C.B600)},
		TerminalFlag{1200, u64(C.B1200)},
		TerminalFlag{1800, u64(C.B1800)},
		TerminalFlag{2400, u64(C.B2400)},
		TerminalFlag{4800, u64(C.B4800)},
		TerminalFlag{9600, u64(C.B9600)},
		TerminalFlag{19200, u64(C.B19200)},
		TerminalFlag{38400, u64(C.B38400)},
		TerminalFlag{57600, u64(C.B57600)},
		TerminalFlag{115200, u64(C.B115200)},
		TerminalFlag{230400, u64(C.B230400)},
	]! {
		if value == if to_native { pair.darwin } else { pair.native } {
			return if to_native { pair.native } else { pair.darwin }
		}
	}
	return none
}

fn terminal_from_native(native &C.termios, destination &DarwinTerminal) i32 {
	$if macos {
		C.memcpy(destination, native, 72)
		return 0
	}
	$if linux {
		input := terminal_flags(native.c_iflag, unsafe { &terminal_input_flags[0] }, terminal_input_flags.len, false) or { return 45 }
		mut output := u64(native.c_oflag)
		mut tabs := u64(0)
		if output & u64(C.TABDLY) == u64(C.XTABS) {
			output &= ~u64(C.TABDLY)
			tabs = 4
		}
		output = terminal_flags(output, unsafe { &terminal_output_flags[0] }, terminal_output_flags.len, false) or { return 45 }
		control := terminal_flags(u64(native.c_cflag) & ~(u64(C.CBAUD) | u64(C.CIBAUD)), unsafe { &terminal_control_flags[0] }, terminal_control_flags.len, false) or { return 45 }
		local := terminal_flags(native.c_lflag, unsafe { &terminal_local_flags[0] }, terminal_local_flags.len, false) or { return 45 }
		output_rate := C.cfgetospeed(native)
		input_rate := C.cfgetispeed(native)
		// Linux encodes zero input baud as "follow output". Darwin reports
		// the effective rate after applying a zero input baud.
		input_speed := terminal_speed(if input_rate == u64(C.B0) { output_rate } else { input_rate }, false) or { return 45 }
		output_speed := terminal_speed(output_rate, false) or { return 45 }
		unsafe {
			destination.input = input
			destination.output = output | tabs
			destination.control = control
			destination.local = local
			destination.padding = 0
			destination.input_speed = input_speed
			destination.output_speed = output_speed
			for index, native_index in terminal_character_indices {
				if native_index < 0 {
					destination.characters[index] = 0xff
					continue
				}
				character := native.c_cc[native_index]
				destination.characters[index] = if index != 16 && index != 17 && character == C._POSIX_VDISABLE {
					u8(0xff)
				} else {
					character
				}
			}
		}
		return 0
	}
	return 45
}

fn terminal_to_native(source &DarwinTerminal, native &C.termios, soft bool) i32 {
	$if macos {
		C.memcpy(native, source, 72)
		return 0
	}
	$if linux {
		input := terminal_flags(source.input, unsafe { &terminal_input_flags[0] }, terminal_input_flags.len, true) or { return 45 }
		output := terminal_flags(source.output & ~u64(4), unsafe { &terminal_output_flags[0] }, terminal_output_flags.len, true) or { return 45 }
		local := terminal_flags(source.local, unsafe { &terminal_local_flags[0] }, terminal_local_flags.len, true) or { return 45 }
		mut control := u64(native.c_cflag)
		if !soft && source.control & 1 == 0 {
			control = terminal_flags(source.control, unsafe { &terminal_control_flags[0] }, terminal_control_flags.len, true) or { return 45 }
			output_speed := terminal_speed(source.output_speed, true) or { return 22 }
			input_speed := terminal_speed(if source.input_speed == 0 {
				source.output_speed
			} else {
				source.input_speed
			}, true) or { return 22 }
			unsafe { native.c_cflag = control }
			if C.cfsetospeed(native, output_speed) != 0 || C.cfsetispeed(native, input_speed) != 0 {
				return darwin_native_error(unsafe { *C.ios_errno_address() })
			}
		}
		for index, native_index in terminal_character_indices {
			character := source.characters[index]
			if native_index < 0 {
				if character != 0xff { return 45 }
				continue
			}
			// Linux uses zero to disable control characters. Reject a literal
			// NUL binding rather than silently turning an enabled binding off.
			if index != 16 && index != 17 && character == 0 { return 45 }
			unsafe {
				native.c_cc[native_index] = if index != 16 && index != 17 && character == 0xff {
					u8(C._POSIX_VDISABLE)
				} else {
					character
				}
			}
		}
		unsafe {
			native.c_iflag = input
			native.c_oflag = output | if source.output & 4 != 0 { u64(C.XTABS) } else { u64(0) }
			native.c_lflag = local
		}
		return 0
	}
	return 45
}

fn darwin_tcgetattr(fd i32, destination &DarwinTerminal) i32 {
	previous := unsafe { *C.ios_errno_address() }
	mut native := C.termios{}
	if C.tcgetattr(fd, unsafe { &native }) != 0 { return darwin_ioctl_result(-1, previous) }
	if destination == unsafe { nil } {
		darwin_set_errno(14)
		return -1
	}
	// Convert into stack storage first; failures never leave partial output.
	converted := unsafe { &DarwinTerminal(C.__builtin_alloca(72)) }
	result := terminal_from_native(unsafe { &native }, converted)
	if result != 0 {
		darwin_set_errno(result)
		return -1
	}
	C.memcpy(destination, converted, 72)
	darwin_set_errno(previous)
	return 0
}

fn darwin_tcsetattr(fd i32, action i32, source &DarwinTerminal) i32 {
	previous := unsafe { *C.ios_errno_address() }
	if action & ~i32(0x13) != 0 || action & 3 == 3 {
		darwin_set_errno(22)
		return -1
	}
	mut native := C.termios{}
	if C.tcgetattr(fd, unsafe { &native }) != 0 { return darwin_ioctl_result(-1, previous) }
	if source == unsafe { nil } {
		darwin_set_errno(14)
		return -1
	}
	result := terminal_to_native(source, unsafe { &native }, action & 0x10 != 0)
	if result != 0 {
		darwin_set_errno(result)
		return -1
	}
	native_action := action & 3
	$if macos {
		return darwin_ioctl_result(C.tcsetattr(fd, action, unsafe { &native }), previous)
	}
	return darwin_ioctl_result(C.tcsetattr(fd, native_action, unsafe { &native }), previous)
}

fn terminal_symbol(symbol string) ?u64 {
	return match symbol {
		'_tcgetattr' { u64(unsafe { voidptr(darwin_tcgetattr) }) }
		'_tcsetattr' { u64(unsafe { voidptr(darwin_tcsetattr) }) }
		else { return none }
	}
}
