// Input sources: /dev/pointer for the mouse and the controlling terminal for
// the keyboard. Both are polled once per frame and never block, so a quiet
// input device cannot hold up the clock.
module main

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
		fd: desktop_open_ro_nonblock(path)
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
	if desktop_read(p.fd, &packet, u64(sizeof(PointerPacket))) != i64(sizeof(PointerPacket)) {
		return none
	}
	return packet
}

fn (mut p PointerDevice) close() {
	if p.fd >= 0 {
		desktop_close(p.fd)
		p.fd = -1
	}
}

// Keyboard puts the terminal in raw mode for as long as the desktop owns the
// screen. Without it the console would echo keystrokes straight onto the
// framebuffer the compositor is drawing into.
struct Keyboard {
mut:
	fd    int
	saved TerminalState
}

fn open_keyboard() Keyboard {
	mut kbd := Keyboard{
		fd: 0
	}
	kbd.saved = desktop_terminal_raw(kbd.fd)
	return kbd
}

// poll returns every byte waiting on the terminal, or an empty string.
fn (mut kbd Keyboard) poll() string {
	mut buf := [64]u8{}
	n := desktop_read(kbd.fd, &buf[0], 64)
	if n <= 0 {
		return ''
	}
	return unsafe { tos(&buf[0], int(n)).clone() }
}

fn (mut kbd Keyboard) close() {
	desktop_terminal_restore(kbd.fd, mut kbd.saved)
}
