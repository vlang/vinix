// SPDX-License-Identifier: GPL-2.0-or-later
module planguest
#include <time.h>
struct C.timespec { mut: tv_sec i64; tv_nsec i64 }
fn C.fchmod(i32, u32) i32
fn C.futimens(i32, &C.timespec) i32

fn backup_guest_tool(command &char, first &char, second &char, third &char, expected i32) {
	unsafe { args := [&char(c'/usr/sbin/vinix-volume'), command, first, second, third, &char(nil)]!; run_utility(&args[0], expected) }
}
fn backup_guest_times(fd i32, changed bool) {
	mut times := [2]C.timespec{}; times[0].tv_sec = 1700000000; times[1].tv_sec = if changed { 1700002345 } else { 1700001234 }
	check(C.fchmod(fd, if changed { u32(0o604) } else { u32(0o640) }) == 0 && C.futimens(fd, &times[0]) == 0, c'file backup source metadata')
}
@[direct_array_access]
fn backup_guest_source() {
	fd := C.open(c'/root/file-source', C.O_RDWR | C.O_CREAT | C.O_EXCL, u32(0o600)); check(fd >= 0, c'create file backup source'); mut bytes := [65536]u8{}
	for block in 0 .. 3 { for i in 0 .. 65536 { bytes[i] = u8(0x31 + block) }; count := if block == 2 { usize(17) } else { usize(65536) }; check(C.write(fd, &bytes[0], count) == i64(count), c'write file version fixture') }
	backup_guest_times(fd, false); check(C.fsync(fd) == 0 && C.close(fd) == 0, c'flush file backup source')
}
@[direct_array_access]
fn backup_guest_verify(path &char, changed bool) {
	fd := C.open(path, C.O_RDONLY); check(fd >= 0, c'open restored file version'); mut info := C.stat{}; mut bytes := [65536]u8{}
	check(C.fstat(fd, &info) == 0 && info.st_size == 131089 && info.st_uid == 0 && info.st_gid == 0 && info.st_mode & 0o7777 == if changed { 0o604 } else { 0o640 } && info.st_mtim.tv_sec == if changed { 1700002345 } else { 1700001234 }, c'preserved file version metadata')
	for block in 0 .. 3 { count := if block == 2 { usize(17) } else { usize(65536) }; check(C.read(fd, &bytes[0], count) == i64(count), c'read restored file bytes'); for i in 0 .. int(count) { check(bytes[i] == if changed && block == 0 && i == 0 { u8(0x77) } else { u8(0x31 + block) }, c'restored complete old/new version') } }
	check(C.read(fd, &bytes[0], 1) == 0 && C.close(fd) == 0, c'restored file EOF')
}
@[direct_array_access]
fn backup_guest_cycles(count int) {
	for _ in 0 .. count {
		backup_guest_tool(c'backup-file', c'/root/file-source', c'/root/cycle-full', unsafe { nil }, 0)
		backup_guest_tool(c'backup-file-delta', c'/root/cycle-full', c'/root/file-source', c'/root/cycle-delta', 0)
		backup_guest_tool(c'restore-file', c'/root/cycle-full', c'/root/cycle-restored-full', unsafe { nil }, 0)
		backup_guest_tool(c'restore-file-delta', c'/root/cycle-full', c'/root/cycle-delta', c'/root/cycle-restored-delta', 0)
		for path in [&char(c'/root/cycle-full'), &char(c'/root/cycle-delta'), &char(c'/root/cycle-restored-full'), &char(c'/root/cycle-restored-delta')]! { check(C.unlink(path) == 0, c'reclaim file version cycle') }
	}
	C.sleep(13); C.printf(c'PLAN FILE BACKUP CYCLES count=%d\n', count)
}
@[direct_array_access]
fn file_backup_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/root/file-backup-phase', C.O_RDONLY)
	if phase < 0 {
		backup_guest_source(); backup_guest_tool(c'backup-file', c'/root/file-source', c'/root/file-full.vbackup', unsafe { nil }, 0)
		fd := C.open(c'/root/file-source', C.O_RDWR); byte := u8(0x77); check(fd >= 0 && C.pwrite(fd, &byte, 1, 0) == 1, c'change file version'); backup_guest_times(fd, true); check(C.fsync(fd) == 0 && C.close(fd) == 0, c'flush changed file version')
		backup_guest_tool(c'backup-file-delta', c'/root/file-full.vbackup', c'/root/file-source', c'/root/file-delta.vbackup', 0)
		backup_guest_tool(c'restore-file', c'/root/file-full.vbackup', c'/root/file-restored-full', unsafe { nil }, 0); backup_guest_verify(c'/root/file-restored-full', false)
		backup_guest_tool(c'restore-file-delta', c'/root/file-full.vbackup', c'/root/file-delta.vbackup', c'/root/file-restored-delta', 0); backup_guest_verify(c'/root/file-restored-delta', true)
		backup_guest_tool(c'restore-file', c'/root/file-full.vbackup', c'/root/file-restored-full', unsafe { nil }, 1); backup_guest_verify(c'/root/file-restored-full', false)
		backup_guest_tool(c'backup-file', c'/root/file-source', c'/root/file-wrong-base', unsafe { nil }, 0)
		backup_guest_tool(c'restore-file-delta', c'/root/file-wrong-base', c'/root/file-delta.vbackup', c'/root/file-refused', 1); check(C.open(c'/root/file-refused', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'wrong base leaves no destination')
		backup_guest_cycles(20); mut before := Heap{}; mut after := Heap{}; heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before); backup_guest_cycles(20); heap_snapshot(mut after)
		C.printf(c'PLAN FILE BACKUP LARGE before=%ld after=%ld\n', before.large, after.large); check(before.large == after.large && before.count == after.count, c'file backup large retention')
		for i in 0 .. before.count { C.printf(c'PLAN FILE BACKUP RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i]); check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'file backup slab retention') }
		marker := C.open(c'/root/file-backup-phase', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); check(marker >= 0 && C.write(marker, c'1', 1) == 1 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist file backup phase')
		C.printf(c'PLAN FILE BACKUP PASSED\n')
	} else {
		check(C.close(phase) == 0, c'close file backup phase'); backup_guest_verify(c'/root/file-restored-full', false); backup_guest_verify(c'/root/file-restored-delta', true)
		backup_guest_tool(c'restore-file', c'/root/file-full.vbackup', c'/root/file-boot-full', unsafe { nil }, 0); backup_guest_verify(c'/root/file-boot-full', false)
		backup_guest_tool(c'restore-file-delta', c'/root/file-full.vbackup', c'/root/file-delta.vbackup', c'/root/file-boot-delta', 0); backup_guest_verify(c'/root/file-boot-delta', true)
		C.printf(c'PLAN FILE BACKUP REBOOT PRESERVED\n')
	}
	directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist file version directory'); C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
