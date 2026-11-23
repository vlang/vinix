// SPDX-License-Identifier: GPL-2.0-or-later
module statmntidfixture

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C._exit(i32)
fn C.chdir(&char) i32
fn C.close(i32) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.read(i32, voidptr, u64) i64
fn C.snprintf(&char, u64, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.strchr(&char, i32) &char
fn C.strcmp(&char, &char) i32
fn C.strstr(&char, &char) &char
fn C.symlink(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.umount2(&char, i32) i32
fn C.unshare(i32) i32
fn C.waitpid(i32, &i32, i32) i32

const mnt_id = u32(0x1000)
const mnt_id_unique = u32(0x4000)
const mount_root = u64(0x2000)
const target_dir = c'/tmp/statmntid/parent'
const original_dir = c'/tmp/statmntid/source'
const alias_dir = c'/tmp/statmntid/parent/alias'
const alias_file = c'/tmp/statmntid/parent/alias/data'

// The musl toolchain's struct statx still calls its mount-ID field padding.
struct Statx {
mut:
	mask u32
	block_size u32
	attributes u64
	header_padding [4]u32
	inode u64
	size_fields [2]u64
	attributes_mask u64
	timestamps_and_devices [10]u64
	mount_id u64
	tail [13]u64
}

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX STATMNTID FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn stat_mount(fd i32, path &char, flags i32, mask u32, at_root bool) Statx {
	mut result := Statx{}
	ret := C.syscall(i64(C.SYS_statx), i64(fd), path, u64(u32(flags)), u64(mask), &result)
	need(ret == 0, c'statx succeeded')
	want := if mask & mnt_id_unique != 0 { mnt_id_unique } else { mnt_id }
	need(result.mask & (mnt_id | mnt_id_unique) == want && result.mount_id > 0, c'only the selected mount ID is present')
	need(result.attributes_mask & mount_root != 0, c'mount root attribute is supported')
	need((result.attributes & mount_root != 0) == at_root, c'mount root attribute identifies the attachment root')
	if want == mnt_id_unique {
		need(result.mount_id > u64(0x80000000), c'unique IDs are above the ordinary ID range')
	}
	return result
}

fn fdinfo_mount(fd i32) u64 {
	unsafe {
		mut path := [64]char{}
		mut text := [512]char{}
		C.snprintf(&path[0], u64(path.len), c'/proc/self/fdinfo/%d', fd)
		info := C.open(&path[0], C.O_RDONLY)
		need(info >= 0, c'open fdinfo')
		bytes := C.read(info, &text[0], u64(text.len - 1))
		C.close(info)
		need(bytes > 0 && bytes < text.len, c'read fdinfo')
		line := C.strstr(&text[0], c'mnt_id:')
		mut id := u64(0)
		need(line != nil && C.sscanf(line, c'mnt_id: %lu', &id) == 1, c'parse fdinfo mount ID')
		return id
	}
}

fn mountinfo_id(path &char) u64 {
	unsafe {
		fd := C.open(c'/proc/self/mountinfo', C.O_RDONLY)
		need(fd >= 0, c'open mountinfo')
		mut text := [16384]char{}
		bytes := C.read(fd, &text[0], u64(text.len - 1))
		C.close(fd)
		need(bytes > 0 && bytes < text.len - 1, c'read mount table')
		mut line := &text[0]
		mut point := [128]char{}
		for line[0] != 0 {
			mut id := u64(0)
			if C.sscanf(line, c'%lu %*u %*s %*s %127s', &id, &point[0]) == 2
				&& C.strcmp(&point[0], path) == 0 {
				return id
			}
			next := C.strchr(line, 10)
			if next == nil { break }
			line = next + 1
		}
		return 0
	}
}

fn check_namespace(fd i32, inherited_id u64, inherited_unique u64) {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork namespace probe')
		if child == 0 {
			need(C.unshare(C.CLONE_NEWNS) == 0, c'copy mount namespace')
			held := stat_mount(fd, nil, C.AT_EMPTY_PATH, mnt_id, true)
			held_unique := stat_mount(fd, nil, C.AT_EMPTY_PATH, mnt_id_unique, true)
			need(held.mount_id == inherited_id && held_unique.mount_id == inherited_unique,
				c'inherited descriptor keeps original attachment IDs')
			copy := stat_mount(C.AT_FDCWD, &char(alias_dir), 0, mnt_id, true)
			copy_unique := stat_mount(C.AT_FDCWD, &char(alias_dir), 0, mnt_id_unique, true)
			need(copy.mount_id != inherited_id && copy_unique.mount_id != inherited_unique,
				c'namespace copy has distinct attachment IDs')
			need(mountinfo_id(&char(alias_dir)) == copy.mount_id, c'mountinfo lists the copy ID')
			fresh := C.open(alias_dir, C.O_PATH | C.O_DIRECTORY)
			need(fresh >= 0 && fdinfo_mount(fresh) == copy.mount_id,
				c'new descriptor sees the copied mount')
			C.close(fresh)
			C._exit(0)
		}
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'namespace probe passed')
	}
}

fn check_alias() {
	unsafe {
		source := stat_mount(C.AT_FDCWD, c'/tmp/statmntid/source/data', 0, 0, false)
		parent := stat_mount(C.AT_FDCWD, &char(target_dir), 0, mnt_id, true)
		alias := stat_mount(C.AT_FDCWD, &char(alias_file), 0, mnt_id, false)
		need(source.inode == alias.inode && source.mount_id != alias.mount_id
			&& parent.mount_id != alias.mount_id, c'bind alias has its own ID for the same inode')
		need(mountinfo_id(&char(alias_dir)) == alias.mount_id, c'mountinfo lists the bind ID')
		distinct := stat_mount(C.AT_FDCWD, &char(alias_file), 0, mnt_id | mnt_id_unique, false)
		original := stat_mount(C.AT_FDCWD, c'/tmp/statmntid/source/data', 0, mnt_id_unique, false)
		need(distinct.mount_id != original.mount_id, c'bind alias has its own unique ID')
		need(stat_mount(C.AT_FDCWD, c'/tmp/statmntid/link', 0, 0, false).mount_id == alias.mount_id,
			c'symlink follows the alias')
		need(stat_mount(C.AT_FDCWD, c'/tmp/statmntid/link', C.AT_SYMLINK_NOFOLLOW, 0, false).mount_id
			== stat_mount(C.AT_FDCWD, c'/tmp/statmntid', 0, 0, false).mount_id,
			c'no-follow reports the link attachment')
		fd := C.open(alias_dir, C.O_PATH | C.O_DIRECTORY)
		need(fd >= 0 && fdinfo_mount(fd) == alias.mount_id, c'fdinfo uses the same ordinary ID')
		need(stat_mount(fd, nil, C.AT_EMPTY_PATH, mnt_id_unique, true).mount_id == distinct.mount_id,
			c'NULL path uses the original open attachment')
		need(stat_mount(fd, c'', C.AT_EMPTY_PATH, mnt_id, true).mount_id == alias.mount_id,
			c'empty path uses the original open attachment')
		need(stat_mount(fd, c'data', 0, mnt_id, false).mount_id == alias.mount_id,
			c'relative descriptor lookup retains the bind route')
		need(stat_mount(fd, c'..', 0, mnt_id, true).mount_id == parent.mount_id,
			c'relative parent follows the bind attachment')
		mut magic := [64]char{}
		C.snprintf(&magic[0], u64(magic.len), c'/proc/self/fd/%d', fd)
		need(stat_mount(C.AT_FDCWD, &magic[0], 0, mnt_id, true).mount_id == alias.mount_id,
			c'proc descriptor jump keeps the actual attachment')
		check_namespace(fd, alias.mount_id, distinct.mount_id)
		need(C.chdir(alias_dir) == 0, c'change into bind mount')
		need(stat_mount(C.AT_FDCWD, c'', C.AT_EMPTY_PATH, 0, true).mount_id == alias.mount_id,
			c'empty cwd query carries the saved attachment')
		need(C.chdir(c'/') == 0, c'leave bind mount')
		need(C.umount2(alias_dir, C.MNT_DETACH) == 0, c'lazily detach bind mount')
		need(stat_mount(C.AT_FDCWD, &char(alias_dir), 0, 0, false).mount_id == parent.mount_id,
			c'pathname now sees the uncovered directory')
		need(C.mount(original_dir, alias_dir, nil, C.MS_BIND, nil) == 0, c'replace detached alias')
		replacement := stat_mount(C.AT_FDCWD, &char(alias_dir), 0, mnt_id_unique, true)
		need(replacement.mount_id != distinct.mount_id, c'replacement receives a fresh ID')
		need(stat_mount(fd, nil, C.AT_EMPTY_PATH, mnt_id_unique, true).mount_id == distinct.mount_id
			&& fdinfo_mount(fd) == alias.mount_id, c'held descriptor keeps the detached ID')
		C.close(fd)
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		need(sizeof(Statx) == 256, c'statx test output has ABI size')
		stat_mount(C.AT_FDCWD, c'/', 0, 0, true)
		need(C.mkdir(c'/tmp/statmntid', 0o755) == 0 && C.mkdir(original_dir, 0o755) == 0
			&& C.mkdir(target_dir, 0o755) == 0, c'create mount directories')
		need(C.mount(c'tmpfs', original_dir, c'tmpfs', 0, nil) == 0
			&& C.mount(c'tmpfs', target_dir, c'tmpfs', 0, nil) == 0, c'mount two tmpfs instances')
		data := C.open(c'/tmp/statmntid/source/data', C.O_CREAT | C.O_RDWR, i32(0o644))
		need(data >= 0 && C.close(data) == 0 && C.mkdir(alias_dir, 0o755) == 0, c'create data and alias mountpoint')
		need(C.mount(original_dir, alias_dir, nil, C.MS_BIND, nil) == 0
			&& C.symlink(alias_file, c'/tmp/statmntid/link') == 0, c'attach bind and symlink')
		check_alias()
		C.puts(c'LINUX STATMNTID SUMMARY: aliases=distinct namespaces=distinct detached=preserved')
		C.puts(if reference { c'LINUX STATMNTID REFERENCE: PASS' } else { c'LINUX STATMNTID: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
