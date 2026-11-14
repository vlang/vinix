@[has_globals]
module mouse

import resource
import stat
import fs
import file
import event
import event.eventstruct
import klock
import katomic
import errno
import wakesrc
import devcore
import dev.console
import dev.mouse.packet as ps2packet
import x86.kio
import x86.apic
import x86.idt

@[inline]
fn wait(t int) bool {
	mut timeout := 100000
	if t == 0 {
		for ; timeout != 0; timeout-- {
			status := kio.port_in[u8](0x64)
			if status != 0xff && status & 0x21 == 0x21 {
				return true
			}
		}
	} else {
		for ; timeout != 0; timeout-- {
			if kio.port_in[u8](0x64) & (1 << 1) == 0 {
				return true
			}
		}
	}
	return false
}

@[inline]
fn write(val u8) bool {
	if !wait(1) { return false }
	kio.port_out[u8](0x64, 0xd4)
	if !wait(1) { return false }
	kio.port_out[u8](0x60, val)
	return true
}

@[inline]
fn read() ?u8 {
	if !wait(0) { return none }
	return kio.port_in[u8](0x60)
}

fn command(value u8) bool {
	if !write(value) { return false }
	ack := read() or { return false }
	return ack == 0xfa
}

fn set_sample_rate(rate u8) bool {
	return command(0xf3) && command(rate)
}

fn device_id() ?u8 {
	if !command(0xf2) { return none }
	return read()
}

struct MousePacket {
pub mut:
	flags u8
	x_mov u32
	y_mov u32
}

// PointerPacket is the architecture-neutral compositor ABI also exposed by
// the ARM64 input drivers.  The PS/2 device reports relative motion, so this
// driver integrates it into an absolute position before publishing it through
// /dev/pointer.  Keeping the same node and packet on both architectures means
// framebuffer applications do not need a legacy x86 input path of their own.
struct PointerPacket {
mut:
	x        i32
	y        i32
	max_x    i32
	max_y    i32
	buttons  u32
	pressed  u32
	released u32
	scroll   i32
}

struct Pointer {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

struct Mouse {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	packet_avl bool
	packet     MousePacket

	// QEMU's standard VGA desktop starts at 1024x768.  These are coordinate
	// ranges rather than framebuffer dimensions; userspace scales them to the
	// mode it actually received from Limine.
	pointer_x        int = 511
	pointer_y        int = 383
	pointer_max_x    int = 1023
	pointer_max_y    int = 767
	pointer_buttons  u32
	pointer_pressed  u32
	pointer_released u32
	// Wheel movement since /dev/pointer was last read.
	pointer_scroll   int
	packet_bytes     int
	five_buttons     bool
}

fn (mut this Pointer) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this Pointer) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count < sizeof(PointerPacket) {
		errno.set(errno.einval)
		return none
	}

	this.l.acquire()
	mouse_res.l.acquire()
	packet := PointerPacket{
		x: i32(mouse_res.pointer_x)
		y: i32(mouse_res.pointer_y)
		max_x: i32(mouse_res.pointer_max_x)
		max_y: i32(mouse_res.pointer_max_y)
		buttons: mouse_res.pointer_buttons
		pressed: mouse_res.pointer_pressed
		released: mouse_res.pointer_released
		scroll: i32(mouse_res.pointer_scroll)
	}
	mouse_res.pointer_pressed = 0
	mouse_res.pointer_released = 0
	mouse_res.pointer_scroll = 0
	mouse_res.l.release()
	this.status &= ~file.pollin
	this.l.release()

	unsafe {
		C.memcpy(buf, &packet, sizeof(PointerPacket))
	}
	return i64(sizeof(PointerPacket))
}

fn (mut this Pointer) write(_handle voidptr, _buf voidptr, _loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this Pointer) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Pointer) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this Pointer) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Pointer) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Pointer) grow(_handle voidptr, _new_size u64) ? {
}

fn (mut this Mouse) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	panic('')
}

fn (mut this Mouse) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count != sizeof(MousePacket) {
		errno.set(errno.einval)
		return none
	}

	handle := unsafe { &file.Handle(_handle) }

	mouse_res.l.acquire()

	for mouse_res.packet_avl == false {
		mouse_res.l.release()

		if handle.flags & resource.o_nonblock != 0 {
			errno.set(errno.ewouldblock)
			return none
		}

		event.await_one(mut mouse_res.event, true) or {}

		mouse_res.l.acquire()
	}

	unsafe {
		C.memcpy(buf, &mouse_res.packet, sizeof(MousePacket))
	}
	mouse_res.packet_avl = false

	mouse_res.status &= ~int(file.pollin)

	mouse_res.l.release()

	return sizeof(MousePacket)
}

fn (mut this Mouse) write(_handle voidptr, _buf voidptr, _loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this Mouse) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Mouse) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this Mouse) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Mouse) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Mouse) grow(_handle voidptr, _new_size u64) ? {
}

__global (
	mouse_res        Mouse
	pointer_res      Pointer
	ps2_mouse_vector u8
	// Set when the mouse has been set up again after a loss of power: the
	// next byte it sends is the first of a packet, wherever the handler was.
	ps2_mouse_restart u32
)

fn clamp_pointer_axis(value int, maximum int) int {
	if value < 0 {
		return 0
	}
	if value > maximum {
		return maximum
	}
	return value
}

fn handler() {
	mut decoder := ps2packet.Decoder{}

	for {
		event.await_one(mut int_events[ps2_mouse_vector], true) or {}
		if katomic.cas(mut &ps2_mouse_restart, u32(1), u32(0)) {
			decoder = ps2packet.Decoder{}
		}
		// IRQs can be stale after setup/resume. Never wait for another byte
		// here or consume a keyboard byte from the shared controller.
		if kio.port_in[u8](0x64) & 0x21 != 0x21 {
			continue
		}
		report := decoder.push(kio.port_in[u8](0x60), mouse_res.packet_bytes,
			mouse_res.five_buttons) or { continue }
		wakesrc.report(.pointer)
		current_packet := MousePacket{
			flags: report.flags
			x_mov: u32(report.x)
			y_mov: u32(report.y)
		}

		mouse_res.l.acquire()
		mouse_res.packet = current_packet
		mouse_res.packet_avl = true

		// PS/2 Y motion is positive towards the top of the display, while the
		// framebuffer coordinate system grows downwards.  Button bits 0..2
		// already have the left/right/middle layout used by PointerPacket.
		delta_x := int(i32(current_packet.x_mov))
		delta_y := int(i32(current_packet.y_mov))
		mouse_res.pointer_x = clamp_pointer_axis(mouse_res.pointer_x + delta_x, mouse_res.pointer_max_x)
		mouse_res.pointer_y = clamp_pointer_axis(mouse_res.pointer_y - delta_y, mouse_res.pointer_max_y)
		buttons := report.buttons
		mouse_res.pointer_pressed |= buttons & ~mouse_res.pointer_buttons
		mouse_res.pointer_released |= mouse_res.pointer_buttons & ~buttons
		mouse_res.pointer_buttons = buttons
		mouse_res.pointer_scroll += int(report.scroll)
		mouse_res.l.release()

		mouse_res.status |= file.pollin
		event.trigger(mut mouse_res.event, false)
		mut notify_pointer := false
		pointer_res.l.acquire()
		if pointer_res.status & file.pollin == 0 {
			pointer_res.status |= file.pollin
			notify_pointer = true
		}
		pointer_res.l.release()
		if notify_pointer {
			event.trigger(mut pointer_res.event, false)
		}
	}
}

pub fn initialise() {
	// mouse_res is a global, which V3 zero-fills without applying the struct's
	// field defaults. A pointer range of 0x0 pinned every report at the corner,
	// so the desktop had nothing to place its cursor with.
	mouse_res.pointer_x = 511
	mouse_res.pointer_y = 383
	mouse_res.pointer_max_x = 1023
	mouse_res.pointer_max_y = 767

	mouse_res.stat.size = 0
	mouse_res.stat.blocks = 0
	mouse_res.stat.blksize = 512
	mouse_res.stat.rdev = resource.create_dev_id()
	mouse_res.stat.mode = 0o644 | stat.ifchr

	mouse_res.status |= file.pollout

	fs.devtmpfs_add_device(&mouse_res, 'mouse')

	pointer_res.stat.size = u64(sizeof(PointerPacket))
	pointer_res.stat.blocks = 0
	pointer_res.stat.blksize = u64(sizeof(PointerPacket))
	pointer_res.stat.rdev = resource.create_dev_id()
	pointer_res.stat.mode = 0o666 | stat.ifchr
	// Reads return the current absolute state immediately. POLLIN is raised by
	// the PS/2 handler only when a fresh packet makes the snapshot change.
	pointer_res.status |= file.pollout
	fs.devtmpfs_add_device(&pointer_res, 'pointer')

	// Keep /dev/pointer available for USB even on a machine without i8042.
	// Command replies must be consumed here, with IRQ12 held off.
	if !console.pointer_interrupt(false) || !negotiate() {
		C.kprintf(c'mouse: PS/2 mouse unavailable\n')
		return
	}
	ps2_mouse_vector = idt.allocate_vector()
	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, ps2_mouse_vector, 12, true)
	console.pointer_interrupt(true)
	C.kprintf(c'mouse: PS/2 mouse ready (%d-byte packets)\n', mouse_res.packet_bytes)

	// Resumed with the other devices, after the keyboard controller it is
	// reached through: that one is registered first.
	if _ := devcore.register_driver(devcore.Driver{
		name:    'psmouse'
		bus:     .platform
		suspend: mouse_suspend
		resume:  mouse_resume
	})
	{
		devcore.claim_platform('i8042-aux', 'pnp0f13', 'psmouse')
	}

	spawn handler()
}

// Tell the mouse what it is to be: defaults, the packet format it can do, and
// to start reporting. At boot, and again when it has been without power.
fn negotiate() bool {
	mouse_res.packet_bytes = 3
	mouse_res.five_buttons = false

	if !command(0xf5) || !command(0xf6) { return false }
	// PS/2 Explorer mice expose side buttons only after switching to the
	// four-byte IntelliMouse protocol. An ordinary three-button mouse keeps
	// its original packet format.
	if !set_sample_rate(200) || !set_sample_rate(100) || !set_sample_rate(80) {
		return false
	}
	mut id := device_id() or { return false }
	if id == 3 {
		if !set_sample_rate(200) || !set_sample_rate(200) || !set_sample_rate(80) {
			return false
		}
		id = device_id() or { return false }
	}
	mouse_res.five_buttons = id == 4
	mouse_res.packet_bytes = if id == 3 || id == 4 { 4 } else { 3 }
	return command(0xf4)
}

fn mouse_suspend(mut _ devcore.Device) bool {
	return true
}

// After a suspend to RAM the mouse is as it is after power-on: not
// reporting, in the three-byte format. It is set up as at boot, with its
// interrupt held off in the controller meanwhile: the answers to the commands
// are read here, and the handler would take them for movement. After a
// suspend to idle it lost nothing and is left alone.
fn mouse_resume(mut _ devcore.Device) bool {
	if !devcore.power_lost() {
		return true
	}
	// All ones is a machine with no keyboard controller, and so no mouse on
	// it.
	if kio.port_in[u8](0x64) == 0xff {
		return true
	}
	// Off already if the keyboard controller was resumed first, as it is.
	if !console.pointer_interrupt(false) || !negotiate() { return false }
	for _ in 0 .. 64 {
		if kio.port_in[u8](0x64) & 0x21 != 0x21 {
			break
		}
		kio.port_in[u8](0x60)
	}
	katomic.store(mut &ps2_mouse_restart, u32(1))
	return console.pointer_interrupt(true)
}

// ── A pointer that is not the PS/2 mouse ────────────────────────────────────
//
// A USB mouse or tablet (dev/xhci) moves the same pointer, as /dev/pointer
// gives it: programs read one position whoever moved it. /dev/mouse, which
// hands out the PS/2 mouse's own packets, hears nothing of these.

// Say that the position changed, to whoever is waiting on /dev/pointer.
fn pointer_moved() {
	// A pointer ends a sleep, if it is allowed to.
	wakesrc.report(.pointer)
	mut notify := false
	pointer_res.l.acquire()
	if pointer_res.status & file.pollin == 0 {
		pointer_res.status |= file.pollin
		notify = true
	}
	pointer_res.l.release()
	if notify {
		event.trigger(mut pointer_res.event, false)
	}
}

// A pointer that reports where it is, 0 to `max_x` and 0 to `max_y`, rather
// than how far it moved, gives /dev/pointer its own range: programs scale
// from whatever range they are told.
pub fn usb_declare(absolute bool, max_x int, max_y int) {
	if !absolute || max_x <= 0 || max_y <= 0 {
		return
	}
	mouse_res.l.acquire()
	mouse_res.pointer_max_x = max_x
	mouse_res.pointer_max_y = max_y
	mouse_res.pointer_x = max_x / 2
	mouse_res.pointer_y = max_y / 2
	mouse_res.l.release()
}

pub fn usb_absolute(x int, y int) {
	mouse_res.l.acquire()
	mouse_res.pointer_x = clamp_pointer_axis(x, mouse_res.pointer_max_x)
	mouse_res.pointer_y = clamp_pointer_axis(y, mouse_res.pointer_max_y)
	mouse_res.l.release()
	pointer_moved()
}

// A USB mouse counts downwards as positive, as the screen does.
pub fn usb_relative(dx int, dy int) {
	mouse_res.l.acquire()
	mouse_res.pointer_x = clamp_pointer_axis(mouse_res.pointer_x + dx, mouse_res.pointer_max_x)
	mouse_res.pointer_y = clamp_pointer_axis(mouse_res.pointer_y + dy, mouse_res.pointer_max_y)
	mouse_res.l.release()
	pointer_moved()
}

pub fn usb_scroll(delta int) {
	mouse_res.l.acquire()
	mouse_res.pointer_scroll += delta
	mouse_res.l.release()
	pointer_moved()
}

// The whole button state, bit 0 the left button, bit 1 the right, bit 2 the
// middle: the layout /dev/pointer has.
pub fn usb_buttons(buttons u32) {
	mouse_res.l.acquire()
	changed := buttons != mouse_res.pointer_buttons
	mouse_res.pointer_pressed |= buttons & ~mouse_res.pointer_buttons
	mouse_res.pointer_released |= mouse_res.pointer_buttons & ~buttons
	mouse_res.pointer_buttons = buttons
	mouse_res.l.release()
	if changed {
		pointer_moved()
	}
}
