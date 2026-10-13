// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct EncryptedRequest {
mut:
	data Request
	key [64]u8
}

fn C.geteuid() u32

struct KeyByte { mut: volatile value u8 }

fn erase_key(pointer voidptr, bytes usize) {
	unsafe { for i in usize(0) .. bytes { (&KeyByte(pointer))[i].value = 0 } }
}

// Import exactly one private binary key through a pinned regular descriptor.
// Never place key bytes in argv, diagnostics, a saved plan or a report.
fn read_volume_key(path &char, output &u8) bool {
	fd := C.open(path, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open key'); return false }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size != 64
		|| info.st_mode & 0o077 != 0 || info.st_uid != C.geteuid() { plan_error(c'key must be a private owned regular 64-byte file'); return false }
	mut done := 0
	for done < 64 {
		count := C.read(fd, unsafe { output + done }, usize(64 - done))
		if count < 0 && unsafe { C.errno == C.EINTR } { continue }
		if count <= 0 || count > 64 - done { plan_error(c'incomplete key read'); return false }; done += int(count)
	}
	mut extra := u8(0); defer { erase_key(unsafe { &extra }, 1) }
	for { count := C.read(fd, unsafe { &extra }, 1); if count < 0 && unsafe { C.errno == C.EINTR } { continue }; if count != 0 { plan_error(c'key file changed while reading'); return false }; break }
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_size != 64 || info.st_mode & 0o077 != 0
		|| info.st_uid != C.geteuid() { plan_error(c'key file changed while reading'); return false }
	mut difference := u8(0); unsafe { for i in 0 .. 32 { difference |= output[i] ^ output[i + 32] } }
	if difference == 0 { plan_error(c'XTS requires distinct key halves'); return false }
	return true
}

fn open_encrypted_volume(device &char, keyfile &char, data &Request) i32 {
	mut request := unsafe { &EncryptedRequest(C.alloca(sizeof(EncryptedRequest))) }; unsafe { *request = EncryptedRequest{data: *data} }
	defer { erase_key(request, sizeof(EncryptedRequest)) }
	if !read_volume_key(keyfile, unsafe { &request.key[0] }) { return 1 }
	return open_encrypted_request(device, request)
}

// The caller retains and erases the complete imported-key request.
fn open_encrypted_request(device &char, request &EncryptedRequest) i32 {
	fd := C.open(device, (if request.data.flags == 0 { C.O_RDWR } else { C.O_RDONLY }) | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open encrypted parent'); return 1 }; defer { C.close(fd) }
	if C.ioctl(fd, u64(0x56560006), request) != 0 { C.perror(c'vinix-volume: open encrypted mapping'); return 1 }
	return finish_bundle_report(C.printf(c'/dev/mapper/vinix%u\n', request.data.slot) >= 0)
}
