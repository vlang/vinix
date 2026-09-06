@[has_globals]
module pointerdev

import resource
import fs
import stat
import klock
import katomic
import errno
import file
import event.eventstruct
import aarch64.virtio_input as _
import apple.spi_keyboard

// PointerPacket is the whole of what /dev/pointer reports, and a read always
// answers with the current state rather than replaying a queue: a compositor
// redraws from the latest position anyway, and a queue it drains too slowly
// would only make the cursor lag behind the hardware.
//
// `x`/`y` are raw device coordinates in 0..max_x/0..max_y. The reader scales
// them to its own surface, so a display resize needs nothing from the driver.
//
// `buttons` is the level: bit 0 left, bit 1 right, bit 2 middle. `pressed` and
// `released` are the edges seen since the previous read, so a click that both
// starts and ends between two reads is still reported. `scroll` is the wheel
// delta accumulated over the same interval.
pub struct PointerPacket {
pub mut:
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
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

__global (
	pointer_res = &Pointer(unsafe { nil })
)

fn (mut this Pointer) mmap(_handle voidptr, page u64, flags int) voidptr {
	return unsafe { nil }
}

fn (mut this Pointer) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count < sizeof(PointerPacket) {
		errno.set(errno.einval)
		return none
	}

	this.l.acquire()

	mut apple := [8]int{}
	mut packet := PointerPacket{}
	if spi_keyboard.read_pointer(&apple[0]) {
		packet = PointerPacket{
			x: apple[0]
			y: apple[1]
			max_x: apple[2]
			max_y: apple[3]
			buttons: u32(apple[4])
			pressed: u32(apple[5])
			released: u32(apple[6])
			scroll: apple[7]
		}
	} else {
		// No verified Apple report: preserve the existing QEMU/VirtIO source.
		packet = PointerPacket{
			x: vi_ptr_x
			y: vi_ptr_y
			max_x: vi_ptr_max_x
			max_y: vi_ptr_max_y
			buttons: vi_ptr_buttons
			pressed: vi_ptr_pressed
			released: vi_ptr_released
			scroll: vi_ptr_scroll
		}
		vi_ptr_pressed = 0
		vi_ptr_released = 0
		vi_ptr_scroll = 0
	}

	this.l.release()

	unsafe {
		C.memcpy(buf, &packet, sizeof(PointerPacket))
	}

	return i64(sizeof(PointerPacket))
}

fn (mut this Pointer) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this Pointer) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Pointer) unref(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this Pointer) link(handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Pointer) unlink(handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Pointer) grow(handle voidptr, new_size u64) ? {
	return none
}

// initialise publishes /dev/pointer. It is created even with no pointer
// hardware present, so a reader can tell "no pointer" (max_x == 0) from
// "kernel too old for this device" (open fails) instead of guessing.
pub fn initialise() {
	mut res := &Pointer{}

	res.stat.size = u64(sizeof(PointerPacket))
	res.stat.blocks = 0
	res.stat.blksize = u64(sizeof(PointerPacket))
	res.stat.rdev = resource.create_dev_id()
	res.stat.mode = 0o666 | stat.ifchr

	// A read never blocks, so the node is always ready in both directions.
	res.status |= file.pollin | file.pollout

	pointer_res = res

	fs.devtmpfs_add_device(res, 'pointer')
}
