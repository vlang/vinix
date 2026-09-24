@[has_globals]
module oss

import event.eventstruct
import klock
import stat
import katomic
import resource
import fs
import file
import errno
import usercopy

const ctl_dsp_halt = u64(0x5000)
const ctl_dsp_sync = u64(0x5001)
const ctl_dsp_post = u64(0x5008)
const ctl_dsp_profile = u64(0x40045017)
const ctl_setsong = u64(0x40405902)
const ctl_getsong = u64(0x80405902)
const ctl_dsp_speed = u64(0xc0045002)
const ctl_dsp_stereo = u64(0xc0045003)
const ctl_dsp_setfmt = u64(0xc0045005)
const ctl_dsp_channels = u64(0xc0045006)
const ctl_dsp_setfragment = u64(0xc004500a)
const ctl_dsp_getfmts = u64(0x8004500b)
const ctl_dsp_getcaps = u64(0x8004500f)
const ctl_oss_getversion = u64(0x80044d76)

const oss_version = 0x040100

pub const afmt_query = 0x0
pub const afmt_u8 = 0x8
pub const afmt_s16_le = 0x10
pub const afmt_s8 = 0x40
pub const afmt_u16_le = 0x80
pub const afmt_s32_le = 0x1000

// What an OSS device is before anyone configures it: 8-bit unsigned mono at
// 8 kHz. A program that writes without asking for anything gets this.
const default_fmt = u32(afmt_u8)
const default_rate = u32(8000)
const default_channels = u8(1)

pub interface OssAudioStream {
mut:
	setup_params(fmt u32, rate u32, channels u8)
	change_volume(percentage int)
	volume() int
	play(play bool)
	reset()
	sync_write(buf voidptr, loc u64, count u64) ?i64
	// Bytes a write could hand over right now without waiting.
	writable() u64
	wait_until_empty()
	is_playing() bool
}

pub interface OssAudioDevice {
mut:
	get_output_stream() &OssAudioStream
	name() string
	// Mask of the AFMT_* formats the device plays.
	formats() u32
	refine_fmt(fmt u32) u32
	refine_rate(rate u32) u32
	refine_channels(channels u8) u8
}

pub struct OssDevice {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	device   &OssAudioDevice
	// Fetched once: turning a driver's stream into the interface allocates.
	stream      &OssAudioStream = unsafe { nil }
	song_name   string
	sample_rate u32
	fmt         u32
	channels    u8
	// The open file description that configured or played through the
	// stream. It has the device until it closes, as in OSS: another program
	// asking to play gets EBUSY rather than having its sound interleaved with
	// the owner's, and opening the node only to probe it, as SDL does for
	// /dev/dsp0../dev/dsp64, changes nothing.
	owner voidptr
}

__global (
	oss_devices []&OssDevice
)

pub fn create_device(device &OssAudioDevice) {
	mut oss_device := &OssDevice{
		device:      unsafe { device }
		sample_rate: default_rate
		fmt:         default_fmt
		channels:    default_channels
	}
	oss_device.stream = oss_device.device.get_output_stream()
	oss_device.stat.rdev = resource.create_dev_id()
	oss_device.stat.mode = 0o666 | stat.ifchr

	name := 'dsp${oss_devices.len}'
	fs.devtmpfs_add_device(oss_device, name)
	if oss_devices.len == 0 {
		root := fs.devtmpfs_get_root()
		fs.symlink(root, name, 'dsp')
	}

	create_mixer(oss_device, oss_devices.len)

	oss_devices << oss_device
}

// Linux takes the command as an unsigned int, and musl's ioctl() passes it
// as an int, so every OSS request with the read bit set arrives sign-extended.
fn command(request u64) u64 {
	return request & 0xffffffff
}

fn read_int(argp voidptr) ?int {
	mut value := i32(0)
	if !usercopy.copy_from_user(&value, u64(argp), sizeof(i32)) {
		errno.set(errno.efault)
		return none
	}
	return int(value)
}

fn write_int(argp voidptr, value int) ? {
	v := i32(value)
	if !usercopy.copy_to_user(u64(argp), &v, sizeof(i32)) {
		errno.set(errno.efault)
		return none
	}
}

// claim makes `handle` the owner, or fails with EBUSY if another one is.
fn (mut dev OssDevice) claim(handle voidptr) ? {
	dev.l.acquire()
	defer {
		dev.l.release()
	}
	if dev.owner != unsafe { nil } && dev.owner != handle {
		errno.set(errno.ebusy)
		return none
	}
	dev.owner = handle
}

// A format, rate or channel count takes effect on the next write, as it does
// in OSS: changing one while the stream is running stops it, and the write
// prepares it again with the new parameters.
fn (mut dev OssDevice) stop_for_change() {
	mut stream := dev.stream
	if stream.is_playing() {
		stream.play(false)
		stream.reset()
	}
}

fn (mut dev OssDevice) grow(_handle voidptr, _new_size u64) ? {
	return none
}

fn (mut dev OssDevice) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	return none
}

fn (mut dev OssDevice) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	dev.claim(handle)?
	mut stream := dev.stream
	mut length := count
	if handle != unsafe { nil } {
		open_handle := unsafe { &file.Handle(handle) }
		if open_handle.flags & resource.o_nonblock != 0 {
			room := stream.writable()
			if room == 0 {
				errno.set(errno.eagain)
				return none
			}
			if length > room {
				length = room
			}
		}
	}
	if !stream.is_playing() {
		stream.setup_params(dev.fmt, dev.sample_rate, dev.channels)
	}
	return stream.sync_write(buf, loc, length)
}

fn (mut dev OssDevice) ioctl(handle voidptr, _request u64, argp voidptr) ?int {
	request := command(_request)
	match request {
		ctl_dsp_halt, ctl_dsp_sync, ctl_dsp_speed, ctl_dsp_stereo, ctl_dsp_setfmt,
		ctl_dsp_channels {
			dev.claim(handle)?
		}
		else {}
	}
	match request {
		ctl_dsp_halt {
			mut stream := dev.stream
			stream.play(false)
			stream.reset()
			return 0
		}
		ctl_dsp_sync {
			mut stream := dev.stream
			stream.wait_until_empty()
			return 0
		}
		ctl_dsp_post, ctl_dsp_profile, ctl_dsp_setfragment {
			// Fragments are the driver's to choose. Accepting the request
			// is what OSS does when it cannot honour it exactly.
			return 0
		}
		ctl_setsong {
			ptr := unsafe { &char(argp) }
			dev.song_name = unsafe { cstring_to_vstring(ptr) }
			return 0
		}
		ctl_getsong {
			ptr := unsafe { &char(argp) }
			unsafe {
				C.memcpy(ptr, dev.song_name.str, dev.song_name.len)
				ptr[dev.song_name.len] = 0
			}
			return 0
		}
		ctl_dsp_getfmts {
			write_int(argp, int(dev.device.formats()))?
			return 0
		}
		ctl_dsp_getcaps {
			write_int(argp, 0)?
			return 0
		}
		ctl_oss_getversion {
			write_int(argp, oss_version)?
			return 0
		}
		ctl_dsp_speed {
			requested := read_int(argp)?
			if requested <= 0 {
				write_int(argp, int(dev.sample_rate))?
				return 0
			}
			refined := dev.device.refine_rate(u32(requested))
			if refined != dev.sample_rate {
				dev.stop_for_change()
			}
			dev.sample_rate = refined
			write_int(argp, int(refined))?
			return 0
		}
		ctl_dsp_setfmt {
			fmt := u32(read_int(argp)?)
			if fmt == afmt_query {
				write_int(argp, int(dev.fmt))?
				return 0
			}
			refined := dev.device.refine_fmt(fmt)
			if refined != dev.fmt {
				dev.stop_for_change()
			}
			dev.fmt = refined
			write_int(argp, int(refined))?
			return 0
		}
		ctl_dsp_channels, ctl_dsp_stereo {
			mut requested := read_int(argp)?
			if request == ctl_dsp_stereo {
				requested = if requested != 0 { 2 } else { 1 }
			}
			if requested <= 0 {
				requested = int(dev.channels)
			}
			if requested > 255 {
				requested = 255
			}
			refined := dev.device.refine_channels(u8(requested))
			if refined != dev.channels {
				dev.stop_for_change()
			}
			dev.channels = refined
			answer := if request == ctl_dsp_stereo { int(refined) - 1 } else { int(refined) }
			write_int(argp, answer)?
			return 0
		}
		else {
			print('oss: unhandled ioctl ${request:x}\n')
			return resource.default_ioctl(handle, request, argp)
		}
	}
}

fn (mut dev OssDevice) unref(handle voidptr) ? {
	katomic.dec(mut dev.refcount)

	if handle != dev.owner {
		return
	}

	mut stream := dev.stream
	stream.wait_until_empty()
	stream.play(false)
	stream.reset()

	// The next program starts from the device defaults, not from whatever
	// the last one left behind.
	dev.sample_rate = default_rate
	dev.fmt = default_fmt
	dev.channels = default_channels
	dev.owner = unsafe { nil }
}

fn (mut dev OssDevice) link(_handle voidptr) ? {
	katomic.inc(mut dev.stat.nlink)
}

fn (mut dev OssDevice) unlink(_handle voidptr) ? {
	katomic.dec(mut dev.stat.nlink)
}

fn (mut dev OssDevice) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}
