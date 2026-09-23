@[has_globals]
module oss

import event.eventstruct
import klock
import stat
import fs
import katomic
import resource
import errno

const ctl_mix_read = u64(0xc0345805)
const ctl_mix_write = u64(0xc0345806)
const ctl_mix_extinfo = u64(0xc0dc5804)
const ctl_mixerinfo = u64(0xc470580a)

struct OssMixerInfo {
pub mut:
	dev            i32
	id             [16]char
	name           [32]char
	modify_counter i32
	card_number    i32
	port_number    i32
	handle         [32]char
	magic          i32
	enabled        i32
	caps           i32
	flags          i32
	nrext          i32
	priority       i32
	devnode        [32]char
	legacy_device  i32
	filler         [245]i32
}

struct OssMixExt {
pub mut:
	dev            i32
	ctrl           i32
	entry_type     i32
	max_value      i32
	min_value      i32
	flags          i32
	id             [16]char
	parent         i32
	dummy          i32
	timestamp      i32
	data           [64]char
	enum_present   [32]u8
	control_no     i32
	desc           u32
	ext_name       [32]char
	update_counter i32
	rgb_color      i32
	filler         [6]i32
}

const mixt_devroot = 0
const mixt_group = 1
const mixt_onoff = 2
const mixt_enum = 3
const mixt_monoslider = 4
const mixt_stereoslider = 5
const mixt_message = 6
const mixt_monovu = 7
const mixt_stereovu = 8
const mixt_monopeak = 9
const mixt_stereopeak = 10
const mixt_radiogroup = 11
const mixt_marker = 12
const mixt_value = 13
const mixt_hexvalue = 14
const mixt_slider = 17
const mixt_3d = 18
const mixt_monoslider16 = 19
const mixt_stereoslider16 = 20
const mixt_mute = 21
const mixt_enum_multi = 22

const mixf_readable = 0x1
const mixf_writable = 0x2
const mixf_poll = 0x4
const mixf_hz = 0x8
const mixf_string = 0x10
const mixf_dynamic = 0x10
const mixf_okfail = 0x20
const mixf_flat = 0x40
const mixf_legacy = 0x80
const mixf_centibel = 0x100
const mixf_decibel = 0x200
const mixf_mainvol = 0x400
const mixf_pcmvol = 0x800
const mixf_recvol = 0x1000
const mixf_monvol = 0x2000
const mixf_wide = 0x4000
const mixf_descr = 0x8000
const mixf_disabled = 0x10000

const mixext_scope_input = 0x1
const mixext_scope_output = 0x2

struct OssMixExtRoot {
pub mut:
	id   [16]char
	name [48]char
}

struct OssMixerValue {
pub mut:
	dev       i32
	ctrl      i32
	value     i32
	flags     i32
	timestamp i32
	filler    [8]i32
}

pub struct OssMixerDevice {
pub mut:
	stat           stat.Stat
	refcount       int
	l              klock.Lock
	event          eventstruct.Event
	status         int
	can_mmap       bool
	main_device    &OssDevice
	index          int
	modify_counter int
}

__global (
	oss_mixers []&OssMixerDevice
)

fn create_mixer(main_device &OssDevice, index int) {
	mut oss_mixer := unsafe {
		&OssMixerDevice{
			main_device: main_device
			index:       index
		}
	}
	oss_mixer.stat.rdev = resource.create_dev_id()
	oss_mixer.stat.mode = 0o666 | stat.ifchr

	name := 'mixer${index}'
	fs.devtmpfs_add_device(oss_mixer, name)
	if index == 0 {
		root := fs.devtmpfs_get_root()
		fs.symlink(root, name, 'mixer')
	}

	oss_mixers << oss_mixer
}

fn (mut dev OssMixerDevice) grow(_handle voidptr, _new_size u64) ? {
	return none
}

fn (mut dev OssMixerDevice) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	return none
}

fn (mut dev OssMixerDevice) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	return none
}

fn (mut dev OssMixerDevice) ioctl(handle voidptr, _request u64, argp voidptr) ?int {
	request := command(_request)
	match request {
		ctl_mix_read {
			mut value := unsafe { &OssMixerValue(argp) }
			match value.ctrl {
				2 {
					mut stream := dev.main_device.stream
					value.value = i32(stream.volume())
					return 0
				}
				else {
					errno.set(errno.einval)
					return -1
				}
			}
		}
		ctl_mix_write {
			mut value := unsafe { &OssMixerValue(argp) }
			match value.ctrl {
				2 {
					mut percentage := int(value.value)
					if percentage < 0 {
						percentage = 0
					} else if percentage > 100 {
						percentage = 100
					}
					dev.modify_counter += 1
					mut stream := dev.main_device.stream
					stream.change_volume(percentage)
					return 0
				}
				else {
					errno.set(errno.einval)
					return -1
				}
			}
		}
		ctl_mix_extinfo {
			mut info := unsafe { &OssMixExt(argp) }

			match info.ctrl {
				0 {
					info.entry_type = mixt_devroot
					root := unsafe { &OssMixExtRoot(&info.data) }

					name := '${dev.main_device.device.name()}_main'

					unsafe {
						C.memcpy(&root.id, name.str, name.len + 1)
						C.memcpy(&root.name, name.str, name.len + 1)
					}
					return 0
				}
				1 {
					info.entry_type = mixt_marker
					return 0
				}
				2 {
					info.entry_type = mixt_monoslider
					info.min_value = 0
					info.max_value = 100
					info.flags = mixf_readable | mixf_writable | mixf_mainvol

					name := '${dev.main_device.device.name()}_mainvolume'

					unsafe {
						C.memcpy(&info.ext_name, name.str, name.len + 1)
					}
					return 0
				}
				else {
					errno.set(errno.einval)
					return -1
				}
			}
		}
		ctl_mixerinfo {
			mut info := unsafe { &OssMixerInfo(argp) }

			name := '${dev.main_device.device.name()} mixer'
			dev_name := '/dev/mixer${dev.index}'

			unsafe {
				C.memcpy(&info.id, name.str, name.len + 1)
				C.memcpy(&info.name, name.str, name.len + 1)
				C.memcpy(&info.devnode, dev_name.str, dev_name.len + 1)
			}
			info.modify_counter = i32(dev.modify_counter)
			info.card_number = -1
			info.port_number = 0
			info.enabled = 1
			info.caps = 0
			info.nrext = 3
			info.priority = 1
			info.legacy_device = i32(dev.index)
			return 0
		}
		else {
			print('oss: unhandled mixer ioctl ${request:x}\n')
			return resource.default_ioctl(handle, request, argp)
		}
	}

	return -1
}

fn (mut dev OssMixerDevice) unref(_handle voidptr) ? {
	katomic.dec(mut dev.refcount)
}

fn (mut dev OssMixerDevice) link(_handle voidptr) ? {
	katomic.inc(mut dev.stat.nlink)
}

fn (mut dev OssMixerDevice) unlink(_handle voidptr) ? {
	katomic.dec(mut dev.stat.nlink)
}

fn (mut dev OssMixerDevice) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}
