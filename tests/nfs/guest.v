// SPDX-License-Identifier: GPL-2.0-or-later
// Mission17B qualification only: real NFSv3 libc operations, disposable PID 1.
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
fn C.getuid() int
fn C.geteuid() int

const chunk_size = 65536
const big_size = 100 * 1024 * 1024
const mount_options = 'soft,rsize=65536,wsize=65536'
const small_text = 'mission17b guest-small-v1\n'

fn syscall_error(operation string) IError {
	return error('${operation}: rc=-1 errno=${C.errno}')
}

fn require(ok bool, message string) ! {
	if !ok {
		return error(message)
	}
}

// Bypass stdio buffering: serial markers must be visible while PID 1 is parked.
fn log_line(message string) {
	line := 'M17B:${message}\n'
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

fn mount_share(source string, retry_network bool) ! {
	started := time.sys_mono_now()
	limit := if retry_network { 3 } else { 1 }
	for attempt in 1 .. limit + 1 {
		rc := unsafe { C.mount(source.str, c'/mnt/nfs', c'nfs', 0, mount_options.str) }
		saved := if rc == 0 { 0 } else { C.errno }
		log_line('mount-call source=${source} target=/mnt/nfs rc=${rc} errno=${saved} attempt=${attempt}')
		if rc == 0 { return }
		transient := saved in [C.ENETUNREACH, C.EHOSTUNREACH, C.ENETDOWN, C.ETIMEDOUT, C.ECONNREFUSED]
		if !transient || attempt == limit {
			return error('mount failed source=${source} rc=${rc} errno=${saved}')
		}
		log_line('mount-retry elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
		time.sleep(time.second)
	}
}

fn negative_mount(source string) ! {
	rc := unsafe { C.mount(source.str, c'/mnt-negative', c'nfs', 0, mount_options.str) }
	saved := if rc == 0 { 0 } else { C.errno }
	if rc == 0 {
		C.umount(c'/mnt-negative')
		return error('missing export mount accepted')
	}
	// MOUNT v3 servers may report ACCES, NOENT or PERM for an unexported path.
	require(rc == -1 && saved in [C.EACCES, C.ENOENT, C.EPERM],
		'missing export expected clean denial rc=${rc} errno=${saved}')!
	log_line('missing-export PASS rc=${rc} errno=${saved} attempts=1 userspace=alive source=${source}')
}

fn server_readonly(source string) ! {
	rc := unsafe { C.mount(source.str, c'/mnt-ro', c'nfs', 0, mount_options.str) }
	saved := if rc == 0 { 0 } else { C.errno }
	log_line('readonly-mount-call rc=${rc} errno=${saved} flags=0 source=${source}')
	require(rc == 0, 'server readonly mount failed')!
	require(read_text('/mnt-ro/m17b-ro.txt')! == 'm17b server readonly fixture\n',
		'readonly fixture mismatch')!
	fd := C.open(c'/mnt-ro/m17b-ro.txt', C.O_WRONLY)
	if fd < 0 { return syscall_error('readonly write-open; actual write not reached') }
	defer { C.close(fd) }
	n := C.write(fd, c'X', 1)
	write_errno := if n < 0 { C.errno } else { 0 }
	require(n == -1 && write_errno == C.EROFS,
		'server readonly actual write expected EROFS rc=${n} errno=${write_errno}')!
	// The deferred close runs before the caller unmounts this separate mount.
	log_line('server-readonly PASS flags=0 write_rc=${n} errno=${write_errno} userspace=alive')
}

fn host_edit() ! {
	ensure_absent('/mnt/nfs/guest-ready')!
	ensure_absent('/mnt/nfs/host-updated.txt')!
	fd := open_read('/mnt/nfs/host-small.txt')!
	defer { C.close(fd) }
	before := read_text_fd(fd)!
	require(before == 'host-edit-v1\n', 'host-small.txt must contain exact initial fixture')!
	log_line('host-small initial bytes=${before.len} text_hex=${before.bytes().hex()} sha256=${sha256.hexhash(before)}')
	write_text('/mnt/nfs/guest-ready', 'ready\n')!
	log_line('guest-ready PASS waiting_seconds=90')
	started := time.sys_mono_now()
	deadline := started + u64(90 * time.second)
	mut seen := false
	for time.sys_mono_now() < deadline {
		marker := unsafe { C.open(c'/mnt/nfs/host-updated.txt', C.O_RDONLY) }
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
	input := open_read('/mnt/nfs/host-big.bin')!
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
	back_started := time.sys_mono_now()
	back_input := open_read('/tmp/guest-copy.bin')!
	back_output := create_file('/mnt/nfs/host-roundtrip.bin') or {
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
	readback := hash_file('/mnt/nfs/host-roundtrip.bin')!
	require(returned.bytes == big_size && returned.sha256 == expected && readback.bytes == big_size
		&& readback.sha256 == expected, 'host same-file roundtrip size/SHA256 mismatch')!
	log_line('host-roundtrip PASS bytes=${returned.bytes} sha256=${readback.sha256} elapsed_ms=${(time.sys_mono_now() - back_started) / u64(time.millisecond)}')
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
	output := create_file('/mnt/nfs/guest-big.bin') or {
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
	observed := hash_file('/mnt/nfs/guest-big.bin')!
	require(observed.bytes == big_size && observed.sha256 == expected,
		'guest-big.bin readback size/SHA-256 mismatch')!
	log_line('guest-big PASS bytes=${big_size} generated_sha256=${expected} readback_sha256=${observed.sha256} write_ms=${write_ms} elapsed_ms=${(time.sys_mono_now() - started) / u64(time.millisecond)}')
}

fn directory_ops() ! {
	if C.mkdir(c'/mnt/nfs/m17b-directory', 0o755) != 0 {
		return syscall_error('mkdir /mnt/nfs/m17b-directory')
	}
	write_text('/mnt/nfs/m17b-directory/before.txt', small_text)!
	if C.rename(c'/mnt/nfs/m17b-directory/before.txt', c'/mnt/nfs/m17b-directory/after.txt') != 0 {
		return syscall_error('rename before.txt to after.txt')
	}
	ensure_absent('/mnt/nfs/m17b-directory/before.txt')!
	require(read_text('/mnt/nfs/m17b-directory/after.txt')! == small_text,
		'renamed file contents differ')!
	names := os.ls('/mnt/nfs/m17b-directory')!
	require('after.txt' in names && 'before.txt' !in names,
		'directory listing does not reflect rename')!
	log_line('directory-list PASS names=${names.join(',')}')
	if C.unlink(c'/mnt/nfs/m17b-directory/after.txt') != 0 {
		return syscall_error('unlink after.txt')
	}
	ensure_absent('/mnt/nfs/m17b-directory/after.txt')!
	if C.rmdir(c'/mnt/nfs/m17b-directory') != 0 {
		return syscall_error('rmdir m17b-directory')
	}
	ensure_absent('/mnt/nfs/m17b-directory')!
	log_line('directory-ops PASS mkdir create rename unlink rmdir')
}

// Open existing, never-read data before the serial barrier. The operation after
// shutdown reads real uncached file content, rather than a negative lookup or a
// cached inode attribute. No NFS calls occur during the eight-second quiet period.
fn stopped_server() ! {
	fd := open_read('/mnt/nfs/m17b-stop-probe.bin')!
	log_line('stop-server-ready quiet_seconds=2 wait_seconds=8 retained_rw_mount=1')
	time.sleep(8 * time.second)
	mut buffer := []u8{len: 4096}
	started := time.sys_mono_now()
	n := unsafe { C.read(fd, buffer.data, usize(buffer.len)) }
	saved := if n < 0 { C.errno } else { 0 }
	elapsed := (time.sys_mono_now() - started) / u64(time.millisecond)
	log_line('stopped-server-call operation=read rc=${n} errno=${saved} elapsed_ms=${elapsed}')
	// Do not assert a particular transport errno: ECONNRESET, EIO, ETIMEDOUT,
	// ECONNREFUSED, etc. depend on how nfsd/transport disappeared.
	transport_error := saved in [C.EIO, C.EPIPE, C.ENETDOWN, C.ENETUNREACH, C.ECONNABORTED,
		C.ECONNRESET, C.ENOTCONN, C.ETIMEDOUT, C.ECONNREFUSED, C.EHOSTDOWN, C.EHOSTUNREACH]
	require(n == -1 && transport_error && elapsed <= 20000,
		'stopped server must fail read cleanly within 20000ms rc=${n} errno=${saved} elapsed_ms=${elapsed}')!
	C.close(fd)
	// Prove a local syscall still works; avoid cleanup RPC on the dead server.
	write_text('/tmp/m17b-after-stop.txt', 'userspace alive\n')!
	require(read_text('/tmp/m17b-after-stop.txt')! == 'userspace alive\n',
		'local continuation failed')!
	log_line('stopped-server PASS operation=read rc=${n} errno=${saved} elapsed_ms=${elapsed} limit_ms=20000')
}

fn qualify() ! {
	started := time.sys_mono_now()
	require(os.args.len == 1, 'this static PID1 accepts no arguments')!
	require(C.getuid() == 0 && C.geteuid() == 0, 'AUTH_SYS qualification requires uid=0 euid=0')!
	for path in ['/mnt/nfs', '/mnt-ro', '/mnt-negative', '/tmp', '/etc'] {
		require(os.is_dir(path), 'initramfs missing ${path}')!
	}
	// /etc/hosts includes fecv3, but raw IP avoids assuming kernel hosts support.
	sources := read_text('/etc/m17b-sources')!.split_into_lines()
	require(sources.len == 3 && sources.all(it.contains(':/')), 'invalid source configuration')!
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
	mount_share(sources[0], true)!
	log_line('mount PASS source=${sources[0]} target=/mnt/nfs fs=nfs flags=0 auth=AUTH_SYS uid=0 euid=0 options=${mount_options} hostname_mode=${if sources[0].starts_with('10.0.2.2:') {
		'raw-ip-hosts-unproven'
	} else {
		'configured-hostname'
	}}')
	write_text('/mnt/nfs/guest-small.txt', small_text)!
	require(read_text('/mnt/nfs/guest-small.txt')! == small_text, 'guest-small.txt readback mismatch')!
	log_line('guest-small PASS bytes=${small_text.len} sha256=${sha256.hexhash(small_text)}')
	host_edit()!
	directory_ops()!
	host_big()!
	guest_big()!
	root_names := os.ls('/mnt/nfs')!
	for name in ['host-small.txt', 'guest-small.txt', 'host-big.bin', 'guest-big.bin',
		'host-roundtrip.bin', 'guest-ready', 'host-updated.txt', 'm17b-stop-probe.bin'] {
		require(name in root_names, 'root listing missing ${name}')!
	}
	log_line('root-list PASS names=${root_names.join(',')}')
	if C.umount(c'/mnt/nfs') != 0 { return syscall_error('umount before remount') }
	log_line('umount PASS rc=0 errno=0')
	mount_share(sources[0], false)!
	require(read_text('/mnt/nfs/guest-small.txt')! == small_text, 'remount lost guest-small.txt')!
	require(read_text('/mnt/nfs/guest-ready')! == 'ready\n', 'remount lost ready marker')!
	remount_hash := hash_file('/mnt/nfs/host-roundtrip.bin')!
	require(remount_hash.bytes == big_size, 'remount roundtrip length mismatch')!
	log_line('remount PASS marker_sha256=${sha256.hexhash(small_text)} roundtrip_sha256=${remount_hash.sha256}')
	// Independent mountpoints preserve the real RW mount until shutdown testing.
	negative_mount(sources[2])!
	server_readonly(sources[1])!
	if C.umount(c'/mnt-ro') != 0 { return syscall_error('umount readonly') }
	log_line('readonly-umount PASS rc=0 errno=0')
	stopped_server()!
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
	log_line('START mission=17B chunk_bytes=${chunk_size} big_bytes=${big_size}')
	qualify() or {
		log_line('FAIL ${err.msg()}')
		park(1, started)
		return
	}
	park(0, started)
}
