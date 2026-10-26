// SPDX-License-Identifier: GPL-2.0-or-later
// One administrator-selected service launch; never an account request channel.
module nativeaccountauth

import time

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

struct C.pollfd {
mut:
	fd i32
	events i16
	revents i16
}

fn C.poll(&C.pollfd, uint, i32) i32
fn C.getgid() i32
fn C.getegid() i32

const service_header = 'vinix-android-service-host-v1'
const max_service_frame = 4096

pub struct ServiceLaunch {
pub:
	package_name string
	service      string
	action       string
	apk_sha256   string
}

pub fn verify_root_channel(fd int) !Peer {
	peer := peer_credentials(fd)!
	if peer.uid != 0 { return error('service control channel requires a Unix root peer') }
	return peer
}

// Called only by the root launcher, before exec. The receiver independently
// verifies the peer/frame and then restores CLOEXEC before any APK code runs.
pub fn inherit_root_channel(fd int) ! {
	verify_root_channel(fd)!
	flags := C.fcntl(i32(fd), C.F_GETFD)
	if flags < 0 || C.fcntl(i32(fd), C.F_SETFD, flags & ~C.FD_CLOEXEC) != 0 {
		return error('cannot preserve service control descriptor')
	}
}

fn parse_service_frame(text string) !ServiceLaunch {
	if text.len > max_service_frame || !text.ends_with('\n') || text.count('\n') != 1
		|| !text.bytes().all((it >= 32 && it <= 126) || it == `\t` || it == `\n`) {
		return error('invalid service launch framing')
	}
	fields := text[..text.len - 1].split('\t')
	if fields.len != 5 || fields[0] != service_header || !package_name_valid(fields[1])
		|| !service_identifier(fields[2], true) || !service_identifier(fields[3], false)
		|| !hash_valid(fields[4]) { return error('invalid service launch selector') }
	return ServiceLaunch{fields[1], fields[2], fields[3], fields[4]}
}

fn read_service_frame(fd int) !string {
	deadline := time.sys_mono_now() + 5 * time.second
	mut bytes := []u8{len: max_service_frame + 1}
	mut count := 0
	for count < bytes.len {
		remaining := (deadline - time.sys_mono_now()) / time.millisecond
		if remaining <= 0 { return error('service launch frame deadline expired') }
		mut ready := C.pollfd{fd: i32(fd), events: C.POLLIN}
		status := C.poll(&ready, 1, i32(remaining))
		if status < 0 && C.errno == C.EINTR { continue }
		if status != 1 || ready.revents & C.POLLIN == 0 {
			return error('service launch frame is unavailable')
		}
		n := unsafe { C.recv(i32(fd), &bytes[count], usize(bytes.len - count), C.MSG_DONTWAIT) }
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 { return error('service launch frame ended early') }
		count += int(n)
		if bytes[..count].contains(u8(`\n`)) {
			text := bytes[..count].bytestr()
			parse_service_frame(text)!
			// Reject already queued trailing bytes. Later control input is a
			// protocol error in the host; this channel carries no requests.
			mut extra := u8(0)
			queued := C.recv(i32(fd), &extra, 1, C.MSG_PEEK | C.MSG_DONTWAIT)
			if queued >= 0 || (C.errno != C.EAGAIN && C.errno != C.EWOULDBLOCK) {
				return error('service launch requires one frame and a live root channel')
			}
			return text
		}
	}
	return error('service launch frame exceeds size limit')
}

// Consume once before loading any APK code. The selected identity is checked
// against every real/effective Unix ID and the root-protected APK registry.
pub fn verify_service_frame(fd int, registry Registry, apk string, uid u32, gid u32) !ServiceLaunch {
	verify_root_channel(fd)!
	if uid < 10000 || uid > 19999 || gid < 10000 || gid > 19999
		|| C.getuid() != uid || C.geteuid() != uid || u32(C.getgid()) != gid || u32(C.getegid()) != gid {
		return error('service launch requires the registered current Unix identity')
	}
	launch := parse_service_frame(read_service_frame(fd)!)!
	entry := registry.verify_service(apk, uid, gid, launch.service, launch.action)!
	if entry.package_name != launch.package_name || entry.apk_sha256 != launch.apk_sha256 {
		return error('service launch package or APK pin does not match registry')
	}
	return launch
}
