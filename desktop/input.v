// Input sources: /dev/pointer for the mouse and the controlling terminal for
// the keyboard. Both are polled once per frame and never block, so a quiet
// input device cannot hold up the clock.
module main

fn C.vd_open_ro_nonblock(path &char) int

fn C.vd_read(fd int, buf voidptr, count u64) i64

fn C.vd_set_nonblocking(fd int) int

fn C.vd_termios_size() u64

fn C.vd_term_save(fd int, saved voidptr) int

fn C.vd_term_raw(fd int, saved voidptr) int

fn C.vd_term_restore(fd int, saved voidptr) int

// PointerPacket mirrors the struct the Vinix pointer driver writes. `x`/`y`
// are raw device coordinates spanning 0..max_x/0..max_y; the desktop scales
// them to the screen, so the driver need not know the resolution.
struct PointerPacket {
mut:
	x        int
	y        int
	max_x    int
	max_y    int
	buttons  u32
	pressed  u32
	released u32
	scroll   int
}

// Button bits, in the order the driver reports them.
const button_left = u32(1)

struct PointerDevice {
mut:
	fd int = -1
}

fn open_pointer(path string) PointerDevice {
	return PointerDevice{
		fd: C.vd_open_ro_nonblock(&char(path.str))
	}
}

fn (p &PointerDevice) available() bool {
	return p.fd >= 0
}

// poll answers with the driver's current view. A read that comes up short is
// reported as "nothing new" rather than as a zeroed position, which would
// otherwise yank the cursor to the top left corner.
fn (mut p PointerDevice) poll() ?PointerPacket {
	if p.fd < 0 {
		return none
	}
	mut packet := PointerPacket{}
	if C.vd_read(p.fd, &packet, u64(sizeof(PointerPacket))) != i64(sizeof(PointerPacket)) {
		return none
	}
	return packet
}

fn (mut p PointerDevice) close() {
	if p.fd >= 0 {
		C.vd_close(p.fd)
		p.fd = -1
	}
}

// termios_buffer is an opaque hold for the terminal's saved settings. The
// layout of struct termios belongs to the target's libc, so the shim owns it
// and this side only has to be large enough.
const termios_buffer = 128

// Keyboard puts the terminal in raw mode for as long as the desktop owns the
// screen. Without it the console would echo keystrokes straight onto the
// framebuffer the compositor is drawing into.
struct Keyboard {
mut:
	fd      int
	saved   [termios_buffer]u8
	restore bool
}

fn open_keyboard() Keyboard {
	mut kbd := Keyboard{
		fd: 0
	}
	if C.vd_termios_size() <= u64(termios_buffer) {
		if C.vd_term_save(kbd.fd, &kbd.saved[0]) == 0 {
			if C.vd_term_raw(kbd.fd, &kbd.saved[0]) == 0 {
				kbd.restore = true
			}
		}
	}
	C.vd_set_nonblocking(kbd.fd)
	return kbd
}

// poll returns every byte waiting on the terminal, or an empty string.
fn (mut kbd Keyboard) poll() string {
	mut buf := [64]u8{}
	n := C.vd_read(kbd.fd, &buf[0], 64)
	if n <= 0 {
		return ''
	}
	return unsafe { tos(&buf[0], int(n)).clone() }
}

fn (mut kbd Keyboard) close() {
	if kbd.restore {
		C.vd_term_restore(kbd.fd, &kbd.saved[0])
		kbd.restore = false
	}
}
