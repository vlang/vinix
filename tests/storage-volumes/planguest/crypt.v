// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

#include <sys/uio.h>
#include <sys/sendfile.h>
struct C.iovec { mut: iov_base voidptr; iov_len usize }
fn C.writev(i32, &C.iovec, i32) i64
fn C.readv(i32, &C.iovec, i32) i64
fn C.lseek(i32, i64, i32) i64
fn C.sendfile(i32, i32, &i64, usize) i64

struct CryptRequest {
mut:
	version u32 = 1
	slot u32 = 60
	offset u64 = 15728640
	length u64 = 4096
	flags u64
	key [64]u8
}

fn crypt_tool(parent &char, key &char, readonly bool, expected i32) {
	unsafe {
		arguments := [&char(c'/usr/sbin/vinix-volume'), &char(c'open-crypt'), parent,
			&char(c'60'), &char(c'15728640'), &char(c'4096'), key,
			if readonly { &char(c'ro') } else { &char(nil) }, &char(nil)]!
		run_utility(&arguments[0], expected)
	}
}

@[direct_array_access]
fn crypt_key(mut request CryptRequest) {
	for i in 0 .. 64 { request.key[i] = u8(i * 13 + 7) }
}

@[direct_array_access]
fn crypt_data(fd i32, offset i64, expected u8) {
	mut got := [512]u8{}
	check(C.pread(fd, &got[0], 512, offset) == 512, c'crypt read')
	for value in got { check(value == expected, c'crypt plaintext preserved') }
}

@[direct_array_access]
fn planned_crypt(parent &char) {
	unsafe {
		mut request := CryptRequest{}; crypt_key(mut request)
		key := C.open(c'/root/crypt.key', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(key >= 0 && C.write(key, &request.key[0], 64) == 64 && C.fsync(key) == 0 && C.close(key) == 0, c'private binary key fixture')
		check(C.symlink(c'/root/crypt.key', c'/root/crypt-link') == 0 && C.mknod(c'/root/crypt-fifo', C.S_IFIFO | 0o600, 0) == 0, c'unsafe key fixtures')
		crypt_tool(parent, c'/root/crypt-link', false, 1)
		crypt_tool(parent, c'/root/crypt-fifo', false, 1)
		check(C.chmod(c'/root/crypt.key', 0o644) == 0, c'public key fixture'); crypt_tool(parent, c'/root/crypt.key', false, 1)
		check(C.chmod(c'/root/crypt.key', 0o600) == 0 && C.chown(c'/root/crypt.key', 65534, 65534) == 0, c'foreign key fixture'); crypt_tool(parent, c'/root/crypt.key', false, 1)
		check(C.chown(c'/root/crypt.key', 0, 0) == 0, c'restore key owner')
		crypt_tool(c'/root/crypt-fifo', c'/root/crypt.key', true, 1)
		missing(c'/dev/mapper/vinix60')
		crypt_tool(parent, c'/root/crypt.key', false, 0)
		info := status(c'/dev/mapper/vinix60')
		check(info.flags & 64 != 0 && info.flags & 32 == 0 && info.bytes == 4096 && info.sector == 512 && info.start == request.offset, c'encrypted status and no discard')
		tool(c'create', parent, c'61', c'15728640', c'4096', 1)
		missing(c'/dev/mapper/vinix61')
		// Saving plain metadata must refuse before replacing a durable plan.
		prior_fd := C.open(c'/root/saved.vmap', C.O_RDONLY); mut prior := [2112]u8{}; size := C.read(prior_fd, &prior[0], 2112)
		check(prior_fd >= 0 && size > 0 && C.close(prior_fd) == 0, c'plain plan before encrypted save')
		simple(c'save', parent, c'/root/saved.vmap', 1); bundle_unchanged(c'/root/saved.vmap', &prior[0], size)
		fd := C.open(c'/dev/mapper/vinix60', C.O_RDWR); check(fd >= 0, c'open crypto descriptor')
		mut plain := [1024]u8{init: 0x73}; mut got := [1024]u8{}
		check(C.pwrite(fd, &plain[0], 1024, 0) == 1024 && C.pread(fd, &got[0], 1024, 0) == 1024, c'encrypted positioned roundtrip')
		for i in 0 .. 1024 { check(plain[i] == 0x73 && got[i] == plain[i], c'caller plaintext unchanged') }
		raw := C.open(parent, C.O_RDONLY); check(raw >= 0 && C.pread(raw, &got[0], 1024, i64(request.offset)) == 1024 && C.close(raw) == 0, c'raw ciphertext read')
		mut different := false; mut units_differ := false
		for i in 0 .. 512 { if got[i] != plain[i] { different = true }; if got[i] != got[i + 512] { units_differ = true } }
		check(different && units_differ, c'physical ciphertext and per-sector tweaks')
		mut vectors := [2]C.iovec{}
		vectors[0] = C.iovec{iov_base: &plain[0], iov_len: 512}; vectors[1] = C.iovec{iov_base: &plain[512], iov_len: 512}
		check(C.lseek(fd, 1024, C.SEEK_SET) == 1024 && C.writev(fd, &vectors[0], 2) == 1024, c'encrypted gather write')
		vectors[0].iov_base = &got[0]; vectors[1].iov_base = &got[512]
		check(C.lseek(fd, 1024, C.SEEK_SET) == 1024 && C.readv(fd, &vectors[0], 2) == 1024, c'encrypted scatter read')
		for value in got { check(value == 0x73, c'encrypted vector plaintext') }
		copy := C.open(c'/root/crypt-copy', C.O_RDWR | C.O_CREAT | C.O_TRUNC, u32(0o600)); mut at := i64(0)
		check(copy >= 0 && C.sendfile(copy, fd, &at, 512) == 512 && at == 512, c'encrypted sendfile read')
		crypt_data(copy, 0, 0x73); check(C.close(copy) == 0, c'close encrypted copy')
		tool(c'grow', c'/dev/mapper/vinix60', c'8192', nil, nil, 0)
		check(status(c'/dev/mapper/vinix60').generation == info.generation, c'crypto growth retains generation')
		plain = [1024]u8{init: 0xa6}; check(C.pwrite(fd, &plain[0], 512, 4096) == 512 && C.fsync(fd) == 0, c'encrypted grown data')
		crypt_data(fd, 0, 0x73); crypt_data(fd, 4096, 0xa6)
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		check(C.pread(fd, &got[0], 512, 0) < 0 && C.errno == C.ENODEV && C.close(fd) == 0, c'removed held descriptor cannot use erased key')
		// The first 4096 bytes reopen read-only through the same stable tweak units.
		crypt_tool(parent, c'/root/crypt.key', true, 0)
		check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'crypto readonly descriptor')
		fd2 := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); crypt_data(fd2, 0, 0x73); check(C.close(fd2) == 0, c'crypto reopen')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		C.printf(c'PLAN CRYPT PASSED: key policy, ciphertext, vector/sendfile IO, growth, held removal, readonly reopen and plain-plan exclusion\n')
	}
}

@[direct_array_access]
fn crypt_cycles(parent &char, count int) {
	unsafe {
		raw := C.open(parent, C.O_RDWR); check(raw >= 0, c'crypto cycle parent')
		mut request := CryptRequest{length: 512}; crypt_key(mut request)
		mut plain := [512]u8{init: 0x73}; mut got := [512]u8{}
		for _ in 0 .. count {
			check(C.ioctl(raw, u64(0x56560006), &request) == 0, c'crypto cycle import')
			fd := C.open(c'/dev/mapper/vinix60', C.O_RDWR); check(fd >= 0, c'crypto cycle descriptor')
			check(C.pwrite(fd, &plain[0], 512, 0) == 512 && C.pread(fd, &got[0], 512, 0) == 512, c'crypto cycle IO')
			for value in got { check(value == 0x73, c'crypto cycle plaintext') }
			check(C.ioctl(fd, u64(0x56560003), &request) == 0 && C.close(fd) == 0, c'crypto cycle erase and release')
		}
		check(C.close(raw) == 0, c'crypto cycle parent release')
		C.printf(c'PLAN CRYPT CYCLES count=%d\n', count)
	}
}

fn crypt_reordered_boot(parent &char) {
	unsafe {
		missing(c'/dev/mapper/vinix60')
		crypt_tool(parent, c'/root/crypt.key', true, 0)
		fd := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); crypt_data(fd, 0, 0x73); check(C.close(fd) == 0, c'persisted ciphertext reopen')
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		C.printf(c'PLAN CRYPT REORDERED BOOT PRESERVED\n')
	}
}
