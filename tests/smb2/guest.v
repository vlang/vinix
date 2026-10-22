// SPDX-License-Identifier: GPL-2.0-or-later
// Mission17A qualification only: real SMB2 libc operations, disposable PID 1.
module main

import crypto.sha256
import os
import time

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.umount(&char) int
fn C.mkdir(&char, u32) int
fn C.open(&char, int, ...) int
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.lseek(int, i64, int) i64
fn C.dup2(int, int) int
fn C.rename(&char, &char) int
fn C.unlink(&char) int
fn C.rmdir(&char) int

const chunk_size = 65536
const big_size = 100 * 1024 * 1024
// Public disposable fixture only. Never interpolate these options into a log.
const mount_options = 'user=m17a,domain=WORKGROUP,password=M17a-disposable-only!'
const bad_options = 'user=m17a,domain=WORKGROUP,password=M17a-intentionally-wrong!'
const small_text = 'mission17a guest-small-v1\n'

fn syscall_error(operation string) IError {
	return error('${operation}: errno=${C.errno}')
}

fn require(ok bool, message string) ! {
	if !ok {
		return error(message)
	}
}

// Bypass stdio buffering: serial markers must be visible while PID 1 is parked.
fn log_line(message string) {
	line := 'M17A:${message}\n'
	write_all(1, line.bytes()) or {}
}

fn write_all(fd int, data []u8) ! {
	mut offset := 0
	for offset < data.len {
		n := unsafe { C.write(fd, &data[offset], usize(data.len - offset)) }
		if n < 0 && C.errno == C.EINTR {
			continue
		}
		if n <= 0 {
			return syscall_error('write fd=${fd} offset=${offset}')
		}
		offset += int(n)
	}
}

fn read_chunk(fd int, mut buffer []u8) !int {
	for {
		n := unsafe { C.read(fd, buffer.data, usize(buffer.len)) }
		if n < 0 && C.errno == C.EINTR {
			continue
		}
		if n < 0 {
			return syscall_error('read fd=${fd}')
		}
		return int(n)
	}
	return 0
}

fn open_read(path string) !int {
	fd := unsafe { C.open(&char(path.str), C.O_RDONLY) }
	if fd < 0 {
		return syscall_error('open ${path}')
	}
	return fd
}

fn create_file(path string) !int {
	fd := unsafe { C.open(&char(path.str), C.O_CREAT | C.O_TRUNC | C.O_WRONLY, int(0o644)) }
	if fd < 0 {
		return syscall_error('create ${path}')
	}
	return fd
}

fn close_checked(fd int) ! {
	if C.close(fd) != 0 {
		return syscall_error('close fd=${fd}')
	}
}

fn write_text(path string, text string) ! {
	fd := create_file(path)!
	write_all(fd, text.bytes()) or {
		C.close(fd)
		return err
	}
	close_checked(fd)!
}

// Bounded text reads tolerate short reads and never consume a large fixture into RAM.
fn read_text_fd(fd int) !string {
	mut buffer := []u8{len: 4096}
	mut data := []u8{}
	for {
		n := read_chunk(fd, mut buffer)!
		if n == 0 {
			break
		}
		if data.len + n > chunk_size {
			return error('small text exceeds 64 KiB')
		}
		data << buffer[..n]
	}
	return data.bytestr()
}

fn read_text(path string) !string {
	fd := open_read(path)!
	data := read_text_fd(fd) or {
		C.close(fd)
		return err
	}
	close_checked(fd)!
	return data
}

fn ensure_absent(path string) ! {
	fd := unsafe { C.open(&char(path.str), C.O_RDONLY) }
	if fd >= 0 {
		C.close(fd)
		return error('expected absent path: ${path}; use a fresh host share')
	}
	if C.errno != C.ENOENT {
		return syscall_error('expected ENOENT for ${path}')
	}
}

fn mount_share(retry_network bool) ! {
	started := time.sys_mono_now()
	limit := if retry_network { 3 } else { 1 }
	for attempt in 1 .. limit + 1 {
		rc := unsafe { C.mount(c'//10.0.2.2/share', c'/mnt', c'smb2', 0, mount_options.str) }
		saved := C.errno
		if rc == 0 { return }
		transient := saved in [C.ENETUNREACH, C.EHOSTUNREACH, C.ENETDOWN, C.ETIMEDOUT, C.ECONNREFUSED]
		if !transient || attempt == limit {
			return error('mount share failed rc=${rc} errno=${saved} attempts=${attempt}')
		}
		log_line('mount-retry attempt=${attempt} errno=${saved} elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
		time.sleep(time.second)
	}
}

fn negative_mount(source string, options string, expected int, label string) ! {
	// Exactly one attempt, including for EACCES. Never log credentials.
	rc := unsafe { C.mount(source.str, c'/mnt', c'smb2', 0, options.str) }
	saved := C.errno
	if rc == 0 {
		C.umount(c'/mnt')
		return error('negative mount accepted case=${label}')
	}
	require(rc == -1 && saved == expected,
		'negative mount case=${label} expected_errno=${expected} rc=${rc} errno=${saved}')!
	log_line('negative-mount PASS case=${label} rc=${rc} errno=${saved} attempts=1 userspace=alive')
}

fn guest_readonly() ! {
	// Anonymous guest, flags=0: EROFS must originate from server share policy.
	if C.mount(c'//10.0.2.2/guest', c'/mnt', c'smb2', 0, c'guest') != 0 {
		return syscall_error('mount anonymous guest share flags=0')
	}
	require(read_text('/mnt/host-small.txt')! == 'host-edit-v2\n', 'guest share read mismatch')!
	fd := C.open(c'/mnt/guest-small.txt', C.O_WRONLY)
	saved := C.errno
	if fd >= 0 { C.close(fd) }
	require(fd == -1 && saved == C.EROFS,
		'server readonly write-open expected EROFS fd=${fd} errno=${saved}')!
	log_line('guest-readonly PASS flags=0 write_open=-1 errno=${saved} userspace=alive')
	if C.umount(c'/mnt') != 0 { return syscall_error('umount guest share') }
}

fn host_edit() ! {
	ensure_absent('/mnt/guest-ready')!
	ensure_absent('/mnt/host-updated.txt')!
	fd := open_read('/mnt/host-small.txt')!
	defer { C.close(fd) }
	before := read_text_fd(fd)!
	require(before.len > 0 && before != 'host-edit-v2\n',
		'host-small.txt must contain initial text')!
	log_line('host-small initial bytes=${before.len} text_hex=${before.bytes().hex()} sha256=${sha256.hexhash(before)}')
	write_text('/mnt/guest-ready', 'ready\n')!
	log_line('guest-ready PASS waiting_seconds=90')
	started := time.sys_mono_now()
	deadline := started + u64(90 * time.second)
	mut seen := false
	for time.sys_mono_now() < deadline {
		marker := unsafe { C.open(c'/mnt/host-updated.txt', C.O_RDONLY) }
		if marker >= 0 {
			close_checked(marker)!
			seen = true
			break
		}
		if C.errno != C.ENOENT {
			return syscall_error('wait host-updated.txt')
		}
		time.sleep(100 * time.millisecond)
	}
	require(seen, 'host-updated.txt timeout after 90 seconds')!
	require(C.lseek(fd, 0, C.SEEK_SET) == 0, 'rewind retained host-small.txt descriptor failed')!
	after := read_text_fd(fd)!
	require(after == 'host-edit-v2\n',
		'retained host-small.txt vnode did not expose host-edit-v2 LF; got=${after.bytes().hex()}')!
	log_line('host-edit PASS retained_fd=${fd} bytes=${after.len} sha256=${sha256.hexhash(after)} elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
}

struct StreamHash {
	bytes  int
	sha256 string
}

fn hash_file(path string) !StreamHash {
	fd := open_read(path)!
	defer { C.close(fd) }
	mut hash := sha256.new()
	mut buffer := []u8{len: chunk_size}
	mut count := 0
	for {
		n := read_chunk(fd, mut buffer)!
		if n == 0 {
			break
		}
		count += n
		require(count <= big_size, '${path} exceeds 100 MiB')!
		hash.write(buffer[..n])!
	}
	return StreamHash{count, hash.sum([]).hex()}
}

fn host_big() ! {
	started := time.sys_mono_now()
	input := open_read('/mnt/host-big.bin')!
	output := create_file('/tmp/guest-copy.bin') or {
		C.close(input)
		return err
	}
	// Close both descriptors on any failure before reporting the final outcome.
	source := copy_stream(input, output) or {
		C.close(input)
		C.close(output)
		return err
	}
	close_checked(input) or {
		C.close(output)
		return err
	}
	close_checked(output)!
	copy_ms := (time.sys_mono_now() - started) / u64(time.millisecond)
	local := hash_file('/tmp/guest-copy.bin')!
	expected := source.sha256
	require(source.bytes == big_size && local.bytes == big_size,
		'host copy must be exactly 104857600 bytes')!
	require(local.sha256 == expected, 'host-to-guest copy SHA-256 mismatch')!
	log_line('host-big PASS bytes=${source.bytes} source_sha256=${expected} local_sha256=${local.sha256} copy_ms=${copy_ms} elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
	// Complete the same-file roundtrip as well as testing a distinct guest source.
	back_input := open_read('/tmp/guest-copy.bin')!
	back_output := create_file('/mnt/host-roundtrip.bin') or {
		C.close(back_input)
		return err
	}
	returned := copy_stream(back_input, back_output) or {
		C.close(back_input)
		C.close(back_output)
		return err
	}
	close_checked(back_input) or {
		C.close(back_output)
		return err
	}
	close_checked(back_output)!
	readback := hash_file('/mnt/host-roundtrip.bin')!
	require(returned.bytes == big_size && returned.sha256 == expected && readback.bytes == big_size
		&& readback.sha256 == expected, 'host same-file roundtrip size/SHA256 mismatch')!
	log_line('host-roundtrip PASS bytes=${returned.bytes} sha256=${readback.sha256} elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
}

fn copy_stream(input int, output int) !StreamHash {
	mut buffer := []u8{len: chunk_size}
	mut hash := sha256.new()
	mut count := 0
	for {
		n := read_chunk(input, mut buffer)!
		if n == 0 {
			break
		}
		count += n
		require(count <= big_size, 'host-big.bin exceeds 100 MiB')!
		write_all(output, buffer[..n])!
		hash.write(buffer[..n])!
	}
	return StreamHash{count, hash.sum([]).hex()}
}

fn guest_big() ! {
	started := time.sys_mono_now()
	mut buffer := []u8{len: chunk_size}
	// Repeat this exact block 1600 times. Parent can reproduce it independently.
	for i in 0 .. buffer.len {
		buffer[i] = u8((i * 31 + 17) & 255)
	}
	fd := create_file('/tmp/guest-source.bin')!
	mut hash := sha256.new()
	for _ in 0 .. big_size / chunk_size {
		write_all(fd, buffer) or {
			C.close(fd)
			return err
		}
		hash.write(buffer) or {
			C.close(fd)
			return err
		}
	}
	close_checked(fd)!
	expected := hash.sum([]).hex()
	input := open_read('/tmp/guest-source.bin')!
	output := create_file('/mnt/guest-big.bin') or {
		C.close(input)
		return err
	}
	copy_started := time.sys_mono_now()
	copied := copy_stream(input, output) or {
		C.close(input)
		C.close(output)
		return err
	}
	close_checked(input) or {
		C.close(output)
		return err
	}
	close_checked(output)!
	write_ms := (time.sys_mono_now() - copy_started) / u64(time.millisecond)
	require(copied.bytes == big_size && copied.sha256 == expected,
		'local-to-share copy source size/SHA-256 mismatch')!
	observed := hash_file('/mnt/guest-big.bin')!
	require(observed.bytes == big_size && observed.sha256 == expected,
		'guest-big.bin readback size/SHA-256 mismatch')!
	log_line('guest-big PASS bytes=${big_size} generated_sha256=${expected} readback_sha256=${observed.sha256} write_ms=${write_ms} elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
}

fn directory_ops() ! {
	if C.mkdir(c'/mnt/m17a-directory', 0o755) != 0 {
		return syscall_error('mkdir /mnt/m17a-directory')
	}
	write_text('/mnt/m17a-directory/before.txt', small_text)!
	if C.rename(c'/mnt/m17a-directory/before.txt', c'/mnt/m17a-directory/after.txt') != 0 {
		return syscall_error('rename before.txt to after.txt')
	}
	ensure_absent('/mnt/m17a-directory/before.txt')!
	require(read_text('/mnt/m17a-directory/after.txt')! == small_text,
		'renamed file contents differ')!
	names := os.ls('/mnt/m17a-directory')!
	require('after.txt' in names && 'before.txt' !in names,
		'directory listing does not reflect rename')!
	log_line('directory-list PASS names=${names.join(',')}')
	if C.unlink(c'/mnt/m17a-directory/after.txt') != 0 {
		return syscall_error('unlink after.txt')
	}
	ensure_absent('/mnt/m17a-directory/after.txt')!
	if C.rmdir(c'/mnt/m17a-directory') != 0 {
		return syscall_error('rmdir m17a-directory')
	}
	ensure_absent('/mnt/m17a-directory')!
	log_line('directory-ops PASS mkdir create rename unlink rmdir')
}

fn qualify() ! {
	started := time.sys_mono_now()
	require(os.args.len == 1,
		'this probe accepts no arguments; dispatch regression is a separate optional qualification')!
	require(os.is_dir('/mnt'), 'parent must create /mnt in initramfs')!
	// Creating /etc before polling lets the kernel publish its DHCP resolver.
	os.mkdir_all('/etc')!
	deadline := started + u64(30 * time.second)
	mut ready := false
	for time.sys_mono_now() < deadline {
		resolver := os.read_file('/etc/resolv.conf') or { '' }
		if resolver.contains('nameserver ') {
			ready = true
			break
		}
		time.sleep(100 * time.millisecond)
	}
	require(ready, 'DHCP resolver publication timeout after 30 seconds')!
	log_line('network-ready PASS elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
	mount_share(true)!
	log_line('mount PASS source=//10.0.2.2/share fs=smb2 flags=0 auth_fixture=NTLMv2 credentials=redacted elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
	// /tmp belongs to the local root filesystem, outside the mounted share.
	if !os.is_dir('/tmp') && C.mkdir(c'/tmp', 0o755) != 0 {
		return syscall_error('mkdir /tmp')
	}
	write_text('/mnt/guest-small.txt', small_text)!
	require(read_text('/mnt/guest-small.txt')! == small_text, 'guest-small.txt readback mismatch')!
	log_line('guest-small PASS bytes=${small_text.len} sha256=${sha256.hexhash(small_text)}')
	host_edit()!
	directory_ops()!
	host_big()!
	guest_big()!
	root_names := os.ls('/mnt')!
	for name in ['host-small.txt', 'guest-small.txt', 'host-big.bin', 'guest-big.bin', 'guest-ready',
		'host-updated.txt'] {
		require(name in root_names, 'root listing missing ${name}')!
	}
	log_line('root-list PASS names=${root_names.join(',')}')
	if C.umount(c'/mnt') != 0 {
		return syscall_error('umount /mnt before remount')
	}
	log_line('umount PASS')
	mount_share(false)!
	require(read_text('/mnt/guest-small.txt')! == small_text, 'remount lost guest-small.txt')!
	require(read_text('/mnt/guest-ready')! == 'ready\n', 'remount lost guest-ready')!
	log_line('remount PASS marker_sha256=${sha256.hexhash(small_text)}')
	if C.umount(c'/mnt') != 0 {
		return syscall_error('final umount /mnt')
	}
	negative_mount('//10.0.2.2/share', bad_options, C.EACCES, 'wrong-password')!
	negative_mount('//10.0.2.2/m17a-missing-share', mount_options, C.ENOENT, 'missing-share')!
	guest_readonly()!
	log_line('userspace-continues PASS elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
}

fn park(status int, started u64) {
	log_line('OUTCOME ${if status == 0 { 'PASS' } else { 'FAIL' }} status=${status} elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)} parked=1')
	// Returning from PID 1 would panic the kernel. Parent owns QEMU termination.
	for {
		time.sleep(time.second)
	}
}

fn main() {
	started := time.sys_mono_now()
	// Some minimal roots already have devtmpfs mounted; do not stack another.
	if !os.exists('/dev/com1') {
		os.mkdir_all('/dev') or {
			park(1, started)
			return
		}
		if C.mount(c'devtmpfs', c'/dev', c'devtmpfs', 0, unsafe { nil }) != 0 {
			log_line('FAIL devtmpfs mount errno=${C.errno}')
			park(1, started)
			return
		}
	}
	serial := C.open(c'/dev/com1', C.O_WRONLY)
	if serial < 0 {
		log_line('FAIL serial open errno=${C.errno}')
		park(1, started)
		return
	}
	if C.dup2(serial, 1) < 0 || C.dup2(serial, 2) < 0 {
		log_line('FAIL serial dup2 errno=${C.errno}')
		park(1, started)
		return
	}
	if serial > 2 {
		C.close(serial)
	}
	log_line('START mission=17A chunk_bytes=${chunk_size} big_bytes=${big_size}')
	qualify() or {
		log_line('FAIL ${err.msg()}')
		park(1, started)
		return
	}
	park(0, started)
}
