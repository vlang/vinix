module oss

import event.eventstruct
import klock
import stat
import katomic
import resource
import fs

const ctl_dsp_halt = u64(0x5000)
const ctl_dsp_profile = u64(0x40045017)
const ctl_setsong = u64(0x40405902)
const ctl_getsong = u64(0x80405902)
const ctl_dsp_speed = u64(0xc0045002)
const ctl_dsp_setfmt = u64(0xc0045005)
const ctl_dsp_channels = u64(0xc0045006)

pub const afmt_u8 = 0x8
pub const afmt_s16_le = 0x10
pub const afmt_s8 = 0x40
pub const afmt_u16_le = 0x80
pub const afmt_s32_le = 0x1000

pub interface OssAudioStream {
mut:
	setup_params(fmt u8, rate u32, channels u8)
	change_volume(percentage int)
	play(play bool)
	reset()
	sync_write(buf voidptr, loc u64, count u64) ?i64
	wait_until_empty()
	is_playing() bool
}

pub interface OssAudioDevice {
mut:
	get_output_stream() &OssAudioStream

	refine_fmt(fmt u8) u8
	refine_channels(channels u8) u8
}

pub struct OssDevice {
pub mut:
	stat        stat.Stat
	refcount    int
	l           klock.Lock
	event       eventstruct.Event
	status      int
	can_mmap    bool
	device      &OssAudioDevice
	song_name   string
	sample_rate u32
	fmt         u8
	channels    u8
}

__global (
	oss_devices []&OssDevice
)

pub fn create_device(device &OssAudioDevice) {
	oss_device := &OssDevice{
		device: unsafe { device }
	}

	name := 'dsp${oss_devices.len}'
	fs.devtmpfs_add_device(oss_device, name)
	root := fs.devtmpfs_get_root()
	fs.symlink(root, name, 'dsp')

	create_mixer(oss_device, oss_devices.len)

	oss_devices << oss_device
}

fn (mut dev OssDevice) grow(handle voidptr, new_size u64) ? {
	return none
}

fn (mut dev OssDevice) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return none
}

fn (mut dev OssDevice) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	mut stream := dev.device.get_output_stream()
	if !stream.is_playing() {
		stream.setup_params(dev.fmt, dev.sample_rate, dev.channels)
	}
	return stream.sync_write(buf, loc, count)
}

fn (mut dev OssDevice) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	match request {
		oss.ctl_dsp_halt {
			mut stream := dev.device.get_output_stream()
			stream.play(false)
			stream.reset()
			return 0
		}
		oss.ctl_dsp_profile {
			return 0
		}
		oss.ctl_setsong {
			ptr := &char(argp)
			dev.song_name = unsafe { cstring_to_vstring(ptr) }
			return 0
		}
		oss.ctl_getsong {
			ptr := &char(argp)
			unsafe {
				C.memcpy(ptr, dev.song_name.str, dev.song_name.len)
				ptr[dev.song_name.len] = 0
			}
			return 0
		}
		oss.ctl_dsp_speed {
			dev.sample_rate = u32(unsafe { *&int(argp) })
			return 0
		}
		oss.ctl_dsp_setfmt {
			ptr := &int(argp)
			fmt := u8(unsafe { *ptr })
			refined := dev.device.refine_fmt(fmt)
			if fmt != refined {
				unsafe {
					*ptr = refined
				}
			}
			dev.fmt = refined
			return 0
		}
		oss.ctl_dsp_channels {
			ptr := &int(argp)
			channels := u8(unsafe { *ptr })
			refined := dev.device.refine_channels(channels)
			if channels != refined {
				unsafe {
					*ptr = refined
				}
			}
			dev.channels = refined
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

	mut stream := dev.device.get_output_stream()
	stream.wait_until_empty()
	stream.play(false)
	stream.reset()
}

fn (mut dev OssDevice) link(handle voidptr) ? {
	katomic.inc(mut dev.stat.nlink)
}

fn (mut dev OssDevice) unlink(handle voidptr) ? {
	katomic.dec(mut dev.stat.nlink)
}

fn (mut dev OssDevice) mmap(page u64, flags int) voidptr {
	return 0
}
