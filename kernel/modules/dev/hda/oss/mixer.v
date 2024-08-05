module oss

import event.eventstruct
import klock
import stat
import fs
import katomic
import resource
import errno

const (
	ctl_mix_read = u64(0xc0345805)
	ctl_mix_write = u64(0xc0345806)
	ctl_mix_extinfo = u64(0xc0dc5804)
	ctl_mixerinfo = u64(0xc470580a)
)

struct OssMixerInfo {
pub mut:
	dev int
	id [16]char
	name [32]char
	modify_counter int
	card_number int
	port_number int
	handle [32]char
	magic int
	enabled int
	caps int
	flags int
	nrext int
	priority int
	devnode [32]char
	legacy_device int
	filler [245]int
}

struct OssMixExt {
pub mut:
	dev int
	ctrl int
	entry_type int
	max_value int
	min_value int
	flags int
	id [16]char
	parent int
	dummy int
	timestamp int
	data [64]char
	enum_present [32]u8
	control_no int
	desc u32
	ext_name [32]char
	update_counter int
	rgb_color int
	filler [6]int
}

const (
	mixt_devroot = 0
	mixt_group = 1
	mixt_onoff = 2
	mixt_enum = 3
	mixt_monoslider = 4
	mixt_stereoslider = 5
	mixt_message = 6
	mixt_monovu = 7
	mixt_stereovu = 8
	mixt_monopeak = 9
	mixt_stereopeak = 10
	mixt_radiogroup = 11
	mixt_marker = 12
	mixt_value = 13
	mixt_hexvalue = 14
	mixt_slider = 17
	mixt_3d = 18
	mixt_monoslider16 = 19
	mixt_stereoslider16 = 20
	mixt_mute = 21
	mixt_enum_multi = 22
)

const (
	mixf_readable = 0x1
	mixf_writable = 0x2
	mixf_poll = 0x4
	mixf_hz = 0x8
	mixf_string = 0x10
	mixf_dynamic = 0x10
	mixf_okfail = 0x20
	mixf_flat = 0x40
	mixf_legacy = 0x80
	mixf_centibel = 0x100
	mixf_decibel = 0x200
	mixf_mainvol = 0x400
	mixf_pcmvol = 0x800
	mixf_recvol = 0x1000
	mixf_monvol = 0x2000
	mixf_wide = 0x4000
	mixf_descr = 0x8000
	mixf_disabled = 0x10000
)

const (
	mixext_scope_input = 0x1
	mixext_scope_output = 0x2
)

struct OssMixExtRoot {
pub mut:
	id [16]char
	name [48]char
}

struct OssMixerValue {
pub mut:
	dev int
	ctrl int
	value int
	flags int
	timestamp int
	filler [8]int
}

pub struct OssMixerDevice {
pub mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
	main_device &OssDevice
	index int
	modify_counter int
	current_volume int
}

__global (
	oss_mixers []&OssMixerDevice
)

fn create_mixer(main_device &OssDevice, index int) {
	mut oss_mixer := unsafe {
		&OssMixerDevice{
			main_device: main_device
			index: index
			current_volume: 50
		}
	}

	name := "mixer${index}"
	fs.devtmpfs_add_device(oss_mixer, name)
	root := fs.devtmpfs_get_root()
	fs.symlink(root, name, "mixer")

	oss_mixers << oss_mixer
}

fn (mut dev OssMixerDevice) grow(handle voidptr, new_size u64) ? {
	return none
}

fn (mut dev OssMixerDevice) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return none
}

fn (mut dev OssMixerDevice) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return none
}

fn (mut dev OssMixerDevice) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	match request {
		ctl_mix_read {
			mut value := unsafe { &OssMixerValue(argp) }
			match value.ctrl {
				2 {
					value.value = dev.current_volume
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
					dev.current_volume = value.value
					dev.modify_counter += 1
					mut stream := dev.main_device.device.get_output_stream()
					stream.change_volume(value.value)
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

					name := "hda_main"

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

					name := "hda_mainvolume"

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

			name := "HDA Mixer"
			dev_name := "/dev/mixer${dev.index}"

			unsafe {
				C.memcpy(&info.id, name.str, name.len + 1)
				C.memcpy(&info.name, name.str, name.len + 1)
				C.memcpy(&info.devnode, dev_name.str, dev_name.len + 1)
			}

			info.modify_counter = dev.modify_counter
			info.card_number = -1
			info.port_number = 0
			info.enabled = 1
			info.caps = 0
			info.nrext = 3
			info.priority = 1
			info.legacy_device = dev.index
			return 0
		}
		else {
			print('oss: unhandled mixer ioctl ${request:x}\n')
			return resource.default_ioctl(handle, request, argp)
		}
	}

	return -1
}

fn (mut dev OssMixerDevice) unref(handle voidptr) ? {
	katomic.dec(mut dev.refcount)
}

fn (mut dev OssMixerDevice) link(handle voidptr) ? {
	katomic.inc(mut dev.stat.nlink)
}

fn (mut dev OssMixerDevice) unlink(handle voidptr) ? {
	katomic.dec(mut dev.stat.nlink)
}

fn (mut dev OssMixerDevice) mmap(page u64, flags int) voidptr {
	return 0
}
