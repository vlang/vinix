// SPDX-License-Identifier: GPL-2.0-or-later
// Root Linux/Vinix real-helper fixture. No Android VM or account operations.
module main

import accountuifd
import crypto.rand
import crypto.sha256
import json2
import os
import strconv
import sync.stdatomic as _
import time

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <unistd.h>

pub struct C.iovec {
pub mut:
	iov_base voidptr
	iov_len  usize
}

pub struct C.msghdr {
pub mut:
	msg_name       voidptr
	msg_namelen    u32
	msg_iov        &C.iovec
	msg_iovlen     usize
	msg_control    voidptr
	msg_controllen usize
	msg_flags      int
}

pub struct C.cmsghdr {
pub mut:
	cmsg_len   usize
	cmsg_level int
	cmsg_type  int
}

fn C.recvmsg(int, &C.msghdr, int) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32

struct UiReceipt {
	kind            string = 'vinix-account-ui-controller-v1'
	created_utc     string
	source_revision string
	helper_path     string
	helper_sha256   string
	desktop_uid     u32
	desktop_gid     u32
	window_socket   string
	checks          []string
	scope           string = 'real desktop helper and root UI controller only; no Android Activity, Google account or sign-in'
}

fn require(ok bool, stage string) ! {
	if !ok { return error('account UI controller fixture: ' + stage) }
}

fn digest(path string) !string {
	info := os.lstat(path)!
	require(info.get_filetype() == .regular && info.size > 0 && info.size <= 128 * 1024 * 1024,
		'bounded regular helper executable')!
	mut source := os.open(path)!
	defer { source.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := source.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn receive_handoff(fd int, capability []u8) ![2]i32 {
	mut bytes := [64]u8{}
	mut ancillary := [8]u64{}
	mut vector := C.iovec{ iov_base: unsafe { &bytes[0] }, iov_len: 64 }
	mut message := C.msghdr{
		msg_iov:        &vector
		msg_iovlen:     1
		msg_control:    unsafe { &ancillary[0] }
		msg_controllen: sizeof(ancillary)
	}
	// Linux MSG_CMSG_CLOEXEC | MSG_DONTWAIT: every received fd is protected
	// before any validation or another process can be started.
	count := C.recvmsg(fd, &message, 0x40000040)
	// recvmsg installs complete descriptors even when the data or ancillary
	// message is rejected. Collect every received right before any assertion.
	mut received := [16]i32{}
	mut used := 0
	mut accepted := false
	defer {
		if !accepted {
			for i in 0 .. used {
				if received[i] >= 0 { C.close(received[i]) }
			}
		}
	}
	mut valid := message.msg_controllen <= sizeof(ancillary)
	length := if valid { message.msg_controllen } else { sizeof(ancillary) }
	control := unsafe { &u8(&ancillary[0]) }
	mut offset := usize(0)
	mut messages := 0
	for offset < length {
		if length - offset < C.CMSG_LEN(0) {
			valid = false
			break
		}
		header := unsafe { &C.cmsghdr(&control[offset]) }
		if header.cmsg_len < C.CMSG_LEN(0) {
			valid = false
			break
		}
		available := if header.cmsg_len <= length - offset {
			header.cmsg_len
		} else {
			length - offset
		}
		messages++
		if header.cmsg_level == C.SOL_SOCKET && header.cmsg_type == C.SCM_RIGHTS {
			payload := available - C.CMSG_LEN(0)
			if payload % sizeof(i32) != 0 { valid = false }
			for at := usize(0); at + sizeof(i32) <= payload; at += sizeof(i32) {
				mut descriptor := i32(-1)
				unsafe { C.memcpy(&descriptor, &control[offset + C.CMSG_LEN(0) + at], sizeof(i32)) }
				mut duplicate := false
				for i in 0 .. used {
					if received[i] == descriptor {
						duplicate = true
						break
					}
				}
				if duplicate {
					valid = false
					continue
				}
				received[used] = descriptor
				used++
			}
		} else {
			valid = false
		}
		if header.cmsg_len > length - offset {
			valid = false
			break
		}
		next := C.CMSG_SPACE(header.cmsg_len - C.CMSG_LEN(0))
		if next > length - offset {
			if header.cmsg_len != length - offset { valid = false }
			break
		}
		offset += next
	}
	require(count == 64 && message.msg_flags & (C.MSG_CTRUNC | C.MSG_TRUNC) == 0,
		'exact untruncated WSUI64 handoff')!
	require(valid && messages == 1 && used == 2, 'exact two-fd ancillary message')!
	descriptors := [received[0], received[1]]!
	require(bytes[..8] == [u8(`W`), `S`, `U`, `I`, 0, 1, 0, 0]
		&& bytes[8..16] == [u8(0), 0, 0, 0, 0, 0, 0, 31]
		&& bytes[16..48] == capability
		&& bytes[48..] == [u8(0), 0, 1, 224, 0, 0, 2, 128, 0, 0, 7, 128, 0, 0, 0, 0],
		'private session capability and immutable geometry')!
	for descriptor in descriptors {
		require(descriptor >= 3 && C.fcntl(descriptor, C.F_GETFD) & C.FD_CLOEXEC != 0,
			'close-on-exec transferred descriptors')!
	}
	accepted = true
	return descriptors
}

fn write_receipt(path string, text string) ! {
	fd := unsafe { C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o644) }
	require(fd >= 0, 'exclusively create fresh receipt')!
	defer { C.close(fd) }
	mut offset := 0
	for offset < text.len {
		count := unsafe { C.write(fd, &text.str[offset], usize(text.len - offset)) }
		if count < 0 && C.errno == C.EINTR { continue }
		require(count > 0, 'write receipt')!
		offset += int(count)
	}
}

fn check_surface(fd i32) ! {
	mut info := C.stat{}
	require(C.fstat(fd, &info) == 0 && u32(info.st_mode) & C.S_IFMT == C.S_IFREG
		&& info.st_size == 48 + 480 * 640 * 8
		&& C.fcntl(fd, C.F_GETFL) & C.O_ACCMODE == C.O_RDWR
		&& C.fcntl(fd, 1034) & 6 == 6, 'writable surface with immutable sealed size')!
	mut header := [12]u32{}
	require(C.pread(fd, &header[0], sizeof(header), 0) == sizeof(header)
		&& header[0] == 0x31534656 && header[1] == 1 && header[2] == 48
		&& header[3] == 480 && header[4] == 640 && header[5] == 1920
		&& header[6] == 1 && header[7] <= 1
		&& header[10] == 480 * 640 * 4 && header[11] == 0, 'VSF1 layout')!
	require(C.ftruncate(fd, 48) != 0 && C.ftruncate(fd, u64(info.st_size) + 1) != 0,
		'surface cannot shrink or grow after transfer')!
	length := usize(info.st_size)
	mapping := C.mmap(unsafe { nil }, length, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
	require(mapping != voidptr(-1), 'map received surface')!
	defer { C.munmap(mapping, length) }
	bytes := unsafe { &u8(mapping) }
	// Publish only the inactive buffer. The helper's reader claim uses the same
	// acquire/release protocol as the production nativews renderer.
	require(C.atomic_load_u32(unsafe { bytes + 28 }) == 0
		&& C.atomic_load_u32(unsafe { bytes + 32 }) != 1, 'initial inactive buffer available')!
	mut pixels := unsafe { &u32(bytes + 48 + 480 * 640 * 4) }
	for y in 0 .. 640 {
		for x in 0 .. 480 {
			unsafe {
				pixels[y * 480 + x] = if (x / 40 + y / 40) % 2 == 0 {
					u32(0xff254b76)
				} else {
					u32(0xffd8e7f1)
				}
			}
		}
	}
	C.atomic_store_u32(unsafe { bytes + 28 }, 1)
	C.atomic_store_u32(unsafe { bytes + 36 }, 1)
}

fn run() ! {
	$if !linux {
		return error('account UI controller fixture requires Linux/Vinix')
	}
	require(os.args.len == 7 && C.getuid() == 0 && C.geteuid() == 0,
		'usage (root): account-ui-controller UID GID ABS_HELPER ABS_WINDOW_SOCKET OUTPUT_JSON SOURCE_REVISION')!
	uid := strconv.parse_uint(os.args[1], 10, 32)!
	gid := strconv.parse_uint(os.args[2], 10, 32)!
	require(uid.str() == os.args[1] && gid.str() == os.args[2], 'canonical desktop IDs')!
	output, revision := os.args[5], os.args[6]
	require(os.is_abs_path(output) && !os.exists(output) && !os.is_link(output)
		&& revision.len in [9, 40] && revision.bytes().all(it.is_hex_digit()), 'fresh receipt and source revision')!
	helper_digest := digest(os.args[3])!
	pair := accountuifd.socket_pair()!
	defer { C.close(pair[1]) }
	mut controller := accountuifd.create(pair[0], accountuifd.Config{
		uid:           u32(uid)
		gid:           u32(gid)
		helper:        os.args[3]
		window_socket: os.args[4]
	}) or {
		C.close(pair[0])
		return err
	}
	defer {
		controller.close()
		unsafe { free(controller) }
	}
	capability := rand.bytes(32)!
	defer { unsafe { capability.free() } }
	controller.begin(31, capability)!
	deadline := time.sys_mono_now() + 6 * time.second
	mut ready := false
	for time.sys_mono_now() < deadline {
		tick := controller.tick()!
		require(!tick.ended, 'helper remains alive until terminal account event')!
		if tick.ready {
			require(tick.session == 31, 'readiness session')!
			ready = true
			break
		}
		time.sleep(time.millisecond)
	}
	require(ready, 'helper window CREATED before descriptor transfer')!
	fds := receive_handoff(pair[1], capability)!
	defer {
		C.close(fds[0])
		C.close(fds[1])
	}
	check_surface(fds[0])!
	mut info := C.stat{}
	require(C.fstat(fds[1], &info) == 0 && u32(info.st_mode) & C.S_IFMT == C.S_IFIFO
		&& C.fcntl(fds[1], C.F_GETFL) & C.O_ACCMODE == C.O_RDONLY, 'read-only input FIFO')!
	status := C.fcntl(fds[1], C.F_GETFL)
	require(status >= 0 && C.fcntl(fds[1], C.F_SETFL, status | C.O_NONBLOCK) == 0,
		'nonblocking input observation')!
	// Leave a visible diagnostic checkerboard briefly; this is not Maps UI.
	until := time.sys_mono_now() + time.second
	for time.sys_mono_now() < until {
		tick := controller.tick()!
		require(!tick.ended && !tick.ready, 'steady helper lifetime')!
		time.sleep(10 * time.millisecond)
	}
	controller.end(31)
	mut eof := false
	mut input := [4096]u8{}
	close_deadline := time.sys_mono_now() + 4 * time.second
	for time.sys_mono_now() < close_deadline {
		count := C.read(fds[1], &input[0], sizeof(input))
		if count == 0 {
			eof = true
			break
		}
		require(count > 0 || C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR]!, 'observe helper input close')!
		controller.tick()!
		time.sleep(10 * time.millisecond)
	}
	require(eof && controller.active_session() == 0, 'terminal lifetime EOF closes helper input')!
	mut rejected := false
	controller.begin(32, capability) or { rejected = true }
	require(rejected, 'one attachment per service process')!
	controller.close()
	receipt := UiReceipt{
		created_utc:     time.utc().format_rfc3339()
		source_revision: revision
		helper_path:     os.args[3]
		helper_sha256:   helper_digest
		desktop_uid:     u32(uid)
		desktop_gid:     u32(gid)
		window_socket:   os.args[4]
		checks:          ['real-helper-window-ready', 'WSUI64-session-capability', 'SCM_RIGHTS-two-fds',
			'CLOEXEC', 'sealed-size-VSF1', 'read-only-input-FIFO', 'diagnostic-frame-published',
			'helper-lifetime-EOF-input-close', 'single-use-attachment']
	}
	write_receipt(output, json2.encode(receipt) + '\n')!
	println('ACCOUNT-UI-CONTROLLER-PASS ready handoff seals frame lifetime-eof single-use')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
