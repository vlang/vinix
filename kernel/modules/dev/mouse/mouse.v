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
import x86.kio
import x86.apic
import x86.idt

@[inline]
fn wait(t int) {
	mut timeout := 100000
	if t == 0 {
		for ; timeout != 0; timeout-- {
			if kio.port_in[u8](0x64) & (1 << 0) != 0 {
				return
			}
		}
	} else {
		for ; timeout != 0; timeout-- {
			if kio.port_in[u8](0x64) & (1 << 1) == 0 {
				return
			}
		}
	}
}

@[inline]
fn write(val u8) {
	wait(1)
	kio.port_out[u8](0x64, 0xd4)
	wait(1)
	kio.port_out[u8](0x60, val)
}

@[inline]
fn read() u8 {
	wait(0)
	return kio.port_in[u8](0x60)
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
	x        int
	y        int
	max_x    int
	max_y    int
	buttons  u32
	pressed  u32
	released u32
	scroll   int
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
}

fn (mut this Pointer) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this Pointer) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count < sizeof(PointerPacket) {
		errno.set(errno.einval)
		return none
	}

	mouse_res.l.acquire()
	packet := PointerPacket{
		x: mouse_res.pointer_x
		y: mouse_res.pointer_y
		max_x: mouse_res.pointer_max_x
		max_y: mouse_res.pointer_max_y
		buttons: mouse_res.pointer_buttons
		pressed: mouse_res.pointer_pressed
		released: mouse_res.pointer_released
	}
	mouse_res.pointer_pressed = 0
	mouse_res.pointer_released = 0
	mouse_res.l.release()

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

		mut events := [&mouse_res.event]
		event.await(mut events, true) or {}
		unsafe { events.free() }

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
	mut handler_cycle := 0
	mut current_packet := MousePacket{}
	mut discard_packet := false

	for {
		mut events := [&int_events[ps2_mouse_vector]]
		event.await(mut events, true) or {}
		unsafe { events.free() }

		// we will get some spurious packets at the beginning and they will screw
		// up the alignment of the handler cycle so just ignore everything in
		// the first 250 milliseconds after boot
		if monotonic_clock.tv_sec == 0 && monotonic_clock.tv_nsec < 250000000 {
			kio.port_in[u8](0x60)
		}

		match handler_cycle {
			0 {
				current_packet.flags = read()
				handler_cycle++
				if current_packet.flags & (1 << 6) != 0 || current_packet.flags & (1 << 7) != 0 {
					discard_packet = true
				}
				if current_packet.flags & (1 << 3) == 0 {
					discard_packet = true
				}
				continue
			}
			1 {
				current_packet.x_mov = read()
				handler_cycle++
				continue
			}
			2 {
				current_packet.y_mov = read()
				handler_cycle = 0

				if discard_packet {
					discard_packet = false
					continue
				}
			}
			else {}
		}

		if current_packet.flags & (1 << 4) != 0 {
			current_packet.x_mov = u32(i8(u8(current_packet.x_mov)))
		}
		if current_packet.flags & (1 << 5) != 0 {
			current_packet.y_mov = u32(i8(u8(current_packet.y_mov)))
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
		buttons := u32(current_packet.flags & 0x07)
		mouse_res.pointer_pressed |= buttons & ~mouse_res.pointer_buttons
		mouse_res.pointer_released |= mouse_res.pointer_buttons & ~buttons
		mouse_res.pointer_buttons = buttons
		mouse_res.l.release()

		mouse_res.status |= file.pollin
		event.trigger(mut mouse_res.event, false)
	}
}

pub fn initialise() {
	write(0xf6)
	read()

	write(0xf4)
	read()

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
	// Reads return the current absolute state and never wait for a fresh PS/2
	// interrupt, matching the ARM64 /dev/pointer contract.
	pointer_res.status |= file.pollin | file.pollout
	fs.devtmpfs_add_device(&pointer_res, 'pointer')

	ps2_mouse_vector = idt.allocate_vector()
	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, ps2_mouse_vector, 12, true)

	spawn handler()
}
