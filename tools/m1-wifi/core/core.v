// SPDX-License-Identifier: ISC
// The byte-array wire ABI and credential lifetime match the native utility.
@[translated]
module wificli

#include "wifi_v.h"

struct C.timespec {
mut:
	tv_sec  i64
	tv_nsec i64
}

fn C.vkw_terminal_save(i32) i32
fn C.vkw_terminal_hide(i32) i32
fn C.vkw_terminal_restore(i32) i32
fn C.vkw_errno() i32
fn C.vkw_set_errno(i32)
fn C.vkw_wipe_byte(voidptr)
fn C.vkw_stderr() &C.FILE
fn C.vkw_file_stat(&C.FILE, &i64, &i32) i32
fn C.open(&char, i32, ...i32) i32
fn C.dup(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.ioctl(i32, usize, voidptr) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.perror(&char)
fn C.exit(i32)
fn C._exit(i32)
fn C.atexit(fn ()) i32
fn C.signal(i32, fn (i32)) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...i32) i32
fn C.fprintf(voidptr, &char, ...i32) i32
fn C.snprintf(&char, usize, &char, ...i32) i32
fn C.fflush(voidptr) i32
fn C.putchar(i32) i32
fn C.fopen(&char, &char) voidptr
fn C.fread(voidptr, usize, usize, voidptr) usize
fn C.fwrite(voidptr, usize, usize, voidptr) usize
fn C.fgetc(voidptr) i32
fn C.fclose(voidptr) i32

__global wifi_tty = i32(-1)
__global wifi_changed i32
__global wifi_password [64]u8

fn wipe(pointer voidptr, count usize) {
	unsafe {
		for at := usize(0); at < count; at++ { C.vkw_wipe_byte(&u8(pointer) + at) }
	}
}

@[export: 'vkw_restore']
pub fn restore() {
	unsafe {
		if wifi_changed != 0 && wifi_tty >= 0 { C.vkw_terminal_restore(wifi_tty) }
		wifi_changed = 0
		wipe(&wifi_password[0], 64)
	}
}

@[export: 'vkw_interrupted']
pub fn interrupted(signal i32) {
	restore()
	C._exit(128 + signal)
}

fn le32(pointer &u8) u32 {
	unsafe {
		return u32(pointer[0]) | u32(pointer[1]) << 8 | u32(pointer[2]) << 16 | u32(pointer[3]) << 24
	}
}

fn le16(pointer &u8) u16 {
	unsafe {
		return u16(pointer[0]) | u16(pointer[1]) << 8
	}
}

fn le64(pointer &u8) u64 {
	unsafe {
		return u64(le32(pointer)) | u64(le32(pointer + 4)) << 32
	}
}

fn put32(pointer &u8, value u32) {
	unsafe {
		for i := u32(0); i < 4; i++ { pointer[i] = u8(value >> (8 * i)) }
	}
}

fn die(operation &char) {
	C.perror(operation)
	C.exit(1)
}

fn pause_ms(ms u32) {
	unsafe {
		mut time := C.timespec{ tv_sec: i64(ms / 1000), tv_nsec: i64(ms % 1000) * 1000000 }
		for {
			rc := C.nanosleep(&time, &time)
			if rc >= 0 || C.vkw_errno() != C.EINTR { break }
		}
	}
}

fn status(fd i32, out &u8) {
	unsafe {
		C.memset(out, 0, 256)
		if C.ioctl(fd, C.BW_IOCTL_STATUS, out) < 0 { die(c'Wi-Fi status') }
	}
}

fn show(fd i32) {
	unsafe {
		mut s := [256]u8{}
		status(fd, &s[0])
		names := [c'off', c'chip detected', c'booting', c'firmware ready', c'authenticating',
			c'authenticated link', c'stopped']!
		state := le32(&s[0])
		C.printf(c'state: %s; error: %d; chip revision: %u; DART error: 0x%08x\n', if state < 7 {
			names[state]
		} else {
			c'invalid'
		}, i32(le32(&s[4])), le32(&s[8]), le32(&s[12]))
		C.printf(c'MAC: %02x:%02x:%02x:%02x:%02x:%02x\n', i32(s[32]), i32(s[33]), i32(s[34]), i32(s[35]), i32(s[36]), i32(s[37]))
		C.printf(c'module: %.15s; vendor: %.15s; module revision: %.15s; antenna: %.15s; board: %.31s\n', &s[40], &s[56], &s[72], &s[104], &s[120])
		C.printf(c'radio: %s; scan: %s; networks: %u; scan error: %d\n', if le32(&s[160]) != 0 {
			c'on'
		} else {
			c'off'
		}, if le32(&s[164]) != 0 { c'running' } else { c'idle' }, le32(&s[168]), i32(le32(&s[172])))
		C.printf(c'RX: %lu; TX: %lu; queue drops: %lu\n', usize(le64(&s[16])), usize(le64(&s[24])), usize(le64(&s[152])))
	}
}

fn print_ssid(pointer &u8, count usize) {
	unsafe {
		C.putchar(34)
		for i := usize(0); i < count; i++ {
			b := pointer[i]
			if b >= 32 && b <= 126 && b != 92 && b != 34 {
				C.putchar(i32(b))
			} else {
				C.printf(c'\\x%02x', i32(b))
			}
		}
		C.putchar(34)
	}
}

@[export: 'vkw_valid_networks']
pub fn valid_networks(out &u8) i32 {
	unsafe {
		count := le32(out + 4)
		if le32(out) != 1 || count > 32 || le32(out + 8) > 1 { return 0 }
		for i := u32(0); i < count; i++ {
			e := out + 16 + i * 48
			channel := le16(e + 2)
			rssi := i16(le16(e + 4))
			if e[0] > 32 || e[1] > 1 || channel == 0 || channel > 233 || rssi > 0 || rssi < -127 {
				return 0
			}
		}
		return 1
	}
}

fn networks(fd i32, begin i32) i32 {
	unsafe {
		if begin != 0 && C.ioctl(fd, C.BW_IOCTL_SCAN, nil) < 0 { die(c'Wi-Fi scan') }
		for attempt := u32(0); ; attempt++ {
			mut out := [1552]u8{}
			if C.ioctl(fd, C.BW_IOCTL_NETWORKS, &out[0]) < 0 { die(c'Wi-Fi networks') }
			if valid_networks(&out[0]) == 0 {
				C.fprintf(C.vkw_stderr(), c'Invalid Wi-Fi network response.\n')
				return 1
			}
			if le32(&out[8]) != 0 && begin != 0 && attempt < 160 {
				pause_ms(100)
				continue
			}
			count := le32(&out[4])
			C.printf(c'scan: %s; error: %d; %u network%s\n', if le32(&out[8]) != 0 {
				c'running'
			} else {
				c'idle'
			}, i32(le32(&out[12])), count, if count == 1 { c'' } else { c's' })
			for i := u32(0); i < count; i++ {
				e := &out[0] + 16 + i * 48
				print_ssid(e + 16, usize(e[0]))
				C.printf(c'  %s  channel %u  %d dBm  %02x:%02x:%02x:%02x:%02x:%02x\n', if e[1] != 0 {
					c'secured'
				} else {
					c'open'
				}, i32(le16(e + 2)), i32(i16(le16(e + 4))), i32(e[8]), i32(e[9]), i32(e[10]), i32(e[11]), i32(e[12]), i32(e[13]))
			}
			return if le32(&out[12]) != 0 { 1 } else { 0 }
		}
	}
	return 1
}

fn read_password() usize {
	unsafe {
		wifi_tty = C.open(c'/dev/tty', C.O_RDWR | C.O_CLOEXEC)
		if wifi_tty < 0 { wifi_tty = C.dup(0) }
		if wifi_tty < 0 { die(c'terminal') }
		if C.vkw_terminal_save(wifi_tty) < 0 { die(c'cannot disable password echo') }
		if C.vkw_terminal_hide(wifi_tty) < 0 { die(c'password terminal') }
		wifi_changed = 1
		C.fprintf(C.vkw_stderr(), c'WPA2 passphrase: ')
		C.fflush(C.vkw_stderr())
		mut count := usize(0)
		mut too_long := false
		for {
			mut byte := u8(0)
			rc := C.read(wifi_tty, &byte, 1)
			if rc < 0 && C.vkw_errno() == C.EINTR { continue }
			if rc != 1 {
				restore()
				C.fprintf(C.vkw_stderr(), c'\nPassword input failed.\n')
				C.exit(1)
			}
			if byte == 13 || byte == 10 { break }
			if count < 64 {
				wifi_password[count] = byte
				count++
			} else {
				too_long = true
			}
		}
		C.vkw_terminal_restore(wifi_tty)
		wifi_changed = 0
		C.close(wifi_tty)
		wifi_tty = -1
		C.fprintf(C.vkw_stderr(), c'\n')
		if too_long || count < 8 || count > 63 {
			C.fprintf(C.vkw_stderr(), c'Use an 8–63 character WPA2 passphrase.\n')
			C.exit(1)
		}
		return count
	}
}

fn path_join(out &char, size usize, directory &char, name &char) {
	rc := C.snprintf(out, size, c'%s/%s', directory, name)
	if rc < 0 || usize(rc) >= size {
		C.vkw_set_errno(C.ENAMETOOLONG)
		die(c'firmware path')
	}
}

fn load(fd i32, directory &char) {
	unsafe {
		names := [c'firmware.bin', c'nvram.txt', c'clm.blob', c'txcap.blob']!
		limits := [u64(4 * 1024 * 1024), u64(65536), u64(1024 * 1024), u64(1024 * 1024)]!
		mut path := [4096]char{}
		mut manifest := [128]u8{}
		path_join(&path[0], 4096, directory, c'manifest.bin')
		mf := C.fopen(&path[0], c'rb')
		if usize(mf) == 0 { die(c'manifest') }
		if C.fread(&manifest[0], 1, 128, mf) != 128 || C.fgetc(mf) != C.EOF {
			C.fprintf(C.vkw_stderr(), c'Invalid manifest length.\n')
			C.exit(1)
		}
		C.fclose(mf)
		mut current := [256]u8{}
		status(fd, &current[0])
		if le32(&current[0]) != 1 || le32(&manifest[0]) != le32(&current[8]) || C.memcmp(&manifest[8], &current[40], 16) != 0 || C.memcmp(&manifest[24], &current[56], 16) != 0 || C.memcmp(&manifest[40], &current[72], 16) != 0 || C.memcmp(&manifest[56], &current[104], 16) != 0 || C.memcmp(&manifest[72], &current[120], 32) != 0 {
			C.fprintf(C.vkw_stderr(), c'Manifest does not match the detected chip/board/module; refusing upload.\n')
			C.exit(1)
		}
		mut files := [4]voidptr{}
		mut totals := [4]u32{}
		// Open and validate every file before the first one-shot upload operation.
		for i := u32(0); i < 4; i++ {
			path_join(&path[0], 4096, directory, names[i])
			files[i] = C.fopen(&path[0], c'rb')
			if usize(files[i]) == 0 { die(names[i]) }
			mut size := i64(0)
			mut regular := i32(0)
			if C.vkw_file_stat(&C.FILE(files[i]), &size, &regular) < 0 { die(c'firmware stat') }
			if regular == 0 || size <= 0 || u64(size) > limits[i] {
				C.fprintf(C.vkw_stderr(), c'Invalid size for %s.\n', names[i])
				C.exit(1)
			}
			totals[i] = u32(size)
		}
		for i := u32(0); i < 4; i++ {
			mut chunk := [4112]u8{}
			mut offset := u32(0)
			for offset < totals[i] {
				C.memset(&chunk[0], 0, 4112)
				mut count := totals[i] - offset
				if count > 4096 { count = 4096 }
				put32(&chunk[0], i)
				put32(&chunk[4], totals[i])
				put32(&chunk[8], offset)
				put32(&chunk[12], count)
				if C.fread(&chunk[16], 1, usize(count), files[i]) != usize(count) {
					die(c'firmware read')
				}
				if C.ioctl(fd, C.BW_IOCTL_UPLOAD, &chunk[0]) < 0 { die(c'firmware upload') }
				offset += count
			}
			if C.fgetc(files[i]) != C.EOF {
				C.fprintf(C.vkw_stderr(), c'Firmware changed during upload; reboot before retrying.\n')
				C.exit(1)
			}
			C.fclose(files[i])
		}
		if C.ioctl(fd, C.BW_IOCTL_BOOT, &manifest[0]) < 0 { die(c'firmware boot') }
		show(fd)
	}
}

@[export: 'main']
pub fn cli_main(argc i32, argv &&char) i32 {
	unsafe {
		C.atexit(restore)
		C.signal(C.SIGINT, interrupted)
		C.signal(C.SIGTERM, interrupted)
		C.signal(C.SIGHUP, interrupted)
		if argc < 2 {
			C.fprintf(C.vkw_stderr(), c'Usage: %s status | status-raw FILE | load DIRECTORY | on | off | scan | networks | join SSID | stop\n', argv[0])
			return 2
		}
		fd := C.open(c'/dev/wlan0', C.O_RDWR | C.O_NONBLOCK | C.O_CLOEXEC)
		if fd < 0 { die(c'/dev/wlan0 (requires vinix.apple_wifi=1 and a supported J313 DT)') }
		if C.strcmp(argv[1], c'status') == 0 && argc == 2 {
			show(fd)
		} else if C.strcmp(argv[1], c'status-raw') == 0 && argc == 3 {
			mut s := [256]u8{}
			status(fd, &s[0])
			out := C.fopen(argv[2], c'wb')
			if usize(out) == 0 { die(c'status output') }
			if C.fwrite(&s[0], 1, 256, out) != 256 || C.fclose(out) != 0 { die(c'status write') }
		} else if C.strcmp(argv[1], c'load') == 0 && argc == 3 {
			load(fd, argv[2])
		} else if (C.strcmp(argv[1], c'on') == 0 || C.strcmp(argv[1], c'off') == 0) && argc == 2 {
			mut q := [4]u8{}
			put32(&q[0], u32(C.strcmp(argv[1], c'on') == 0))
			if C.ioctl(fd, C.BW_IOCTL_RADIO, &q[0]) < 0 { die(c'Wi-Fi radio') }
			show(fd)
		} else if C.strcmp(argv[1], c'scan') == 0 && argc == 2 {
			result := networks(fd, 1)
			C.close(fd)
			return result
		} else if C.strcmp(argv[1], c'networks') == 0 && argc == 2 {
			result := networks(fd, 0)
			C.close(fd)
			return result
		} else if C.strcmp(argv[1], c'join') == 0 && argc == 3 {
			size := C.strlen(argv[2])
			if size == 0 || size > 32 {
				C.fprintf(C.vkw_stderr(), c'SSID must contain 1–32 bytes.\n')
				return 2
			}
			count := read_password()
			mut q := [104]u8{}
			put32(&q[0], u32(size))
			put32(&q[4], u32(count))
			C.memcpy(&q[8], argv[2], size)
			C.memcpy(&q[40], &wifi_password[0], count)
			rc := C.ioctl(fd, C.BW_IOCTL_JOIN, &q[0])
			error := C.vkw_errno()
			wipe(&q[0], 104)
			wipe(&wifi_password[0], 64)
			C.vkw_set_errno(error)
			if rc < 0 { die(c'WPA2 join') }
			for i := u32(0); i < 310; i++ {
				mut s := [256]u8{}
				status(fd, &s[0])
				if le32(&s[0]) == 5 {
					show(fd)
					C.printf(c'Layer-2 link authenticated. This driver does not provide an IP stack.\n')
					C.close(fd)
					return 0
				}
				if le32(&s[0]) == 6 {
					show(fd)
					C.close(fd)
					return 1
				}
				pause_ms(100)
			}
			C.fprintf(C.vkw_stderr(), c'Authentication deadline exceeded.\n')
			C.close(fd)
			return 1
		} else if C.strcmp(argv[1], c'stop') == 0 && argc == 2 {
			if C.ioctl(fd, C.BW_IOCTL_STOP, nil) < 0 { die(c'stop') }
			show(fd)
		} else {
			C.fprintf(C.vkw_stderr(), c'Unknown command or argument count.\n')
			C.close(fd)
			return 2
		}
		C.close(fd)
		return 0
	}
}
