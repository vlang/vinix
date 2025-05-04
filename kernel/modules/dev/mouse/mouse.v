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
}

fn (mut this Mouse) mmap(page u64, flags int) voidptr {
	panic('')
}

fn (mut this Mouse) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
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

fn (mut this Mouse) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this Mouse) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Mouse) unref(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this Mouse) link(handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Mouse) unlink(handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Mouse) grow(handle voidptr, new_size u64) ? {
}

__global (
	mouse_res        Mouse
	ps2_mouse_vector u8
)

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

	ps2_mouse_vector = idt.allocate_vector()
	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, ps2_mouse_vector, 12, true)

	spawn handler()
}
