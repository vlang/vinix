// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module planguest

#include <volume.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <elf.h>
#include <sys/auxv.h>
#include <sys/stat.h>

@[c_extern] __global C.stdout voidptr
@[c_extern] __global C.errno i32
fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) i64
fn C.write(i32, voidptr, usize) i64
fn C.pread(i32, voidptr, usize, i64) i64
fn C.pwrite(i32, voidptr, usize, i64) i64
fn C.fsync(i32) i32
fn C.ioctl(i32, u64, ...voidptr) i32
fn C.printf(&char, ...voidptr) i32
fn C.setbuf(voidptr, voidptr)
fn C.pause() i32
fn C.sleep(u32) u32
fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.dup2(i32, i32) i32
fn C.fopen(&char, &char) voidptr
fn C.fclose(voidptr) i32
fn C.fgets(&char, i32, voidptr) &char
fn C.sscanf(&char, &char, ...voidptr) i32
fn C.getauxval(u64) u64
fn C.fstat(i32, &C.stat) i32
fn C.chmod(&char, u32) i32
fn C.chown(&char, u32, u32) i32
fn C.rename(&char, &char) i32
fn C.mknod(&char, u32, u64) i32
fn C.symlink(&char, &char) i32
fn C.unlink(&char) i32
fn C.getpid() i32
fn C.getppid() i32

struct C.stat { st_rdev u64 }

@[typedef]
struct C.Elf64_Phdr {
	p_type u32
	p_flags u32
	p_vaddr u64
	p_memsz u64
}

@[typedef]
struct C.Elf64_Ehdr {
	e_type u16
	e_phoff u64
}

struct Status {
mut:
	version u64
	bytes u64
	sector u64
	flags u64
	reads u64
	writes u64
	read_bytes u64
	write_bytes u64
	flushes u64
	errors u64
	last_error u64
	disk_id u64
	start u64
	slot u64
	generation u64
	reserved u64
}

struct Heap {
mut:
	count int
	sizes [32]i64
	live [32]i64
	large i64
}

fn check(condition bool, message &char) {
	if condition { return }
	C.printf(c'PLAN FAIL: %s errno=%d\n', message, unsafe { C.errno })
	for { C.pause() }
}

fn status(path &char) Status {
	fd := C.open(path, C.O_RDONLY)
	check(fd >= 0, c'open status')
	mut result := Status{}
	check(C.ioctl(fd, u64(0x56560004), &result) == 0 && result.version == 1, c'query status')
	check(C.close(fd) == 0, c'close status')
	return result
}

fn missing(path &char) {
	fd := C.open(path, C.O_RDONLY)
	check(fd < 0 && unsafe { C.errno == C.ENOENT }, c'expected absent mapping')
}

fn tool(command &char, device &char, a &char, b &char, c &char, expected i32) {
	unsafe {
		arguments := [&char(c'/usr/sbin/vinix-volume'), command, device, a, b, c, &char(nil)]!
		child := C.fork()
		check(child >= 0, c'fork utility')
		if child == 0 { C.execv(arguments[0], &arguments[0]); C._exit(127) }
		mut code := i32(0)
		check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'utility exit')
	}
}

fn simple(command &char, device &char, file &char, expected i32) {
	unsafe { tool(command, device, file, &char(nil), &char(nil), expected) }
}

@[direct_array_access]
fn view_data() {
	fd := C.open(c'/dev/mapper/vinix2', C.O_RDONLY)
	check(fd >= 0, c'open restored view')
	mut bytes := [4096]u8{}
	check(C.pread(fd, &bytes[0], 4096, 0) == 4096, c'read restored data')
	for value in bytes { check(value == 0x6d, c'reboot data preserved') }
	check(C.close(fd) == 0, c'close restored view')
	readonly := C.open(c'/dev/mapper/vinix5', C.O_RDWR)
	check(readonly < 0 && unsafe { C.errno == C.EROFS }, c'restored read-only mode')
}

@[direct_array_access]
fn heap_snapshot(mut snapshot Heap) {
	file := C.fopen(c'/proc/slabinfo', c'r')
	check(file != unsafe { nil }, c'open heap snapshot')
	mut text := [256]char{}
	for C.fgets(&text[0], 256, file) != unsafe { nil } {
		mut index := i64(0); mut size := i64(0); mut live := i64(0); mut pages := i64(0)
		if C.sscanf(&text[0], c'size-%ld %ld %ld %ld', &index, &size, &live, &pages) == 4 {
			check(snapshot.count < 32, c'bounded heap classes')
			snapshot.sizes[snapshot.count] = size
			snapshot.live[snapshot.count] = live
			snapshot.count++
		} else if C.sscanf(&text[0], c'large - - %ld', &pages) == 1 { snapshot.large = pages }
	}
	check(C.fclose(file) == 0 && snapshot.count > 0, c'close heap snapshot')
}

fn cycles(parent &char, count int) {
	for _ in 0 .. count {
		simple(c'save', parent, c'/root/saved.vmap', 0)
		simple(c'restore-auto', c'/root/saved.vmap', unsafe { &char(nil) }, 0)
	}
	C.sleep(13)
}

fn fixture_plan(bytes &u8) {
	fd := C.open(c'/etc/vinix/volumes.vmap', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(fd >= 0 && C.write(fd, bytes, 128) == 128 && C.fsync(fd) == 0 && C.close(fd) == 0, c'write boot plan fixture')
}

@[direct_array_access]
fn signature(device &char, value u32) {
	fd := C.open(device, C.O_RDWR)
	mut sector := [512]u8{}
	check(fd >= 0 && C.pread(fd, &sector[0], 512, 0) == 512, c'read duplicate identity fixture')
	for i := 0; i < 4; i++ { sector[440 + i] = u8(value >> (8 * i)) }
	check(C.pwrite(fd, &sector[0], 512, 0) == 512 && C.fsync(fd) == 0 && C.close(fd) == 0, c'change duplicate identity fixture')
}

fn physical_alias(parent &char) {
	fd := C.open(parent, C.O_RDONLY)
	mut info := C.stat{}
	check(fd >= 0 && C.fstat(fd, &info) == 0 && C.close(fd) == 0, c'physical alias identity')
	check(C.mknod(c'/dev/volume-plan-alias', C.S_IFBLK | 0o600, info.st_rdev) == 0, c'physical alias creation')
	check(C.symlink(parent, c'/dev/volume-plan-link') == 0, c'discovery symlink fixture')
}

// The static fixture itself stays alive across the measurement. Touch every
// readable load page so later diagnostic code/data faults do not count as
// save/restore retention (especially with x86's smaller pages).
fn warm_image() {
	unsafe {
		address := C.getauxval(C.AT_PHDR)
		count := C.getauxval(C.AT_PHNUM)
		page := C.getauxval(C.AT_PAGESZ)
		check(address > sizeof(C.Elf64_Ehdr) && count > 0 && count <= 64
			&& C.getauxval(C.AT_PHENT) == sizeof(C.Elf64_Phdr) && page >= 4096 && page <= 65536, c'fixture ELF metadata')
		header := &C.Elf64_Ehdr(address - sizeof(C.Elf64_Ehdr))
		check(header.e_type == C.ET_EXEC && header.e_phoff == sizeof(C.Elf64_Ehdr), c'static fixture ELF layout')
		segments := &C.Elf64_Phdr(address)
		mut checksum := u8(0)
		for i := u64(0); i < count; i++ {
			segment := segments[i]
			if segment.p_type != C.PT_LOAD || segment.p_flags & C.PF_R == 0 { continue }
			check(segment.p_memsz <= 16 * 1024 * 1024 && segment.p_vaddr <= u64(-1) - segment.p_memsz, c'fixture load bounds')
			end := segment.p_vaddr + segment.p_memsz
			for at := segment.p_vaddr; at < end; at = (at / page + 1) * page {
				checksum ^= *(&u8(at))
			}
		}
		C.printf(c'PLAN WARM image=%u\n', u32(checksum))
	}
}

fn allocation_trace(path &char, print bool) {
	fd := C.open(path, C.O_RDONLY)
	if fd < 0 { return } // Ordinary kernels need not enable ALLOC_TRACK.
	mut bytes := [4096]u8{}
	for {
		count := C.read(fd, &bytes[0], 4096)
		if count <= 0 { break }
		if print { C.write(1, &bytes[0], usize(count)) }
	}
	C.close(fd)
}

@[direct_array_access]
fn first_boot(parent &char) {
	unsafe {
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid initial boot plan')
		simple(c'boot-restore', &char(nil), &char(nil), 0)
		tool(c'create', parent, c'2', c'1048576', c'4096', 0)
		arguments := [&char(c'/usr/sbin/vinix-volume'), &char(c'create'), parent, &char(c'5'), &char(c'2097152'), &char(c'8192'), &char(c'ro'), &char(nil)]!
		child := C.fork(); check(child >= 0, c'fork read-only create')
		if child == 0 { C.execv(arguments[0], &arguments[0]); C._exit(127) }
		mut code := i32(0); check(C.waitpid(child, &code, 0) == child && code == 0, c'read-only create')
		fd := C.open(c'/dev/mapper/vinix2', C.O_RDWR); check(fd >= 0, c'open writable view')
		mut data := [4096]u8{init: 0x6d}
		check(C.pwrite(fd, &data[0], 4096, 0) == 4096 && C.fsync(fd) == 0 && C.close(fd) == 0, c'write durable view data')
		simple(c'save', parent, c'/root/saved.vmap', 0)
		original := status(c'/dev/mapper/vinix2').generation
		simple(c'restore', parent, c'/root/saved.vmap', 0)
		check(status(c'/dev/mapper/vinix2').generation == original, c'idempotent restore keeps generation')
		simple(c'remove', c'/dev/mapper/vinix2', &char(nil), 0)
		simple(c'remove', c'/dev/mapper/vinix5', &char(nil), 0)
		// Corrupted on-disk plans cannot create even the first mapping.
		plan_fd := C.open(c'/root/saved.vmap', C.O_RDONLY)
		mut damaged := [128]u8{}
		check(plan_fd >= 0 && C.read(plan_fd, &damaged[0], 128) == 128 && C.close(plan_fd) == 0, c'read corruption fixture')
		damaged[112] ^= 1
		bad_fd := C.open(c'/root/bad.vmap', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(bad_fd >= 0 && C.write(bad_fd, &damaged[0], 128) == 128 && C.close(bad_fd) == 0, c'write corruption fixture')
		simple(c'restore', parent, c'/root/bad.vmap', 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		fixture_plan(&damaged[0])
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		damaged[112] ^= 1
		fixture_plan(&damaged[0])
		check(C.chmod(c'/etc/vinix/volumes.vmap', 0o622) == 0, c'untrusted plan mode')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		check(C.chmod(c'/etc/vinix/volumes.vmap', 0o600) == 0 && C.chmod(c'/etc/vinix', 0o777) == 0, c'untrusted directory mode')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		check(C.chmod(c'/etc/vinix', 0o755) == 0, c'restore trusted directory')
		check(C.chown(c'/etc/vinix/volumes.vmap', 65534, 65534) == 0, c'untrusted plan owner')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		check(C.chown(c'/etc/vinix/volumes.vmap', 0, 0) == 0, c'restore trusted plan owner')
		check(C.rename(c'/etc/vinix/volumes.vmap', c'/etc/vinix/real.vmap') == 0
			&& C.symlink(c'real.vmap', c'/etc/vinix/volumes.vmap') == 0, c'boot plan symlink fixture')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0
			&& C.rename(c'/etc/vinix/real.vmap', c'/etc/vinix/volumes.vmap') == 0, c'restore regular boot plan')
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		// A different physical disk must fail before creating any mapping.
		wrong := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		simple(c'restore', wrong, c'/root/saved.vmap', 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		physical_alias(parent)
		signature(wrong, 0x12345678)
		simple(c'restore-auto', c'/root/saved.vmap', &char(nil), 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		signature(wrong, 0x12345679)
		simple(c'discover', c'/root/saved.vmap', &char(nil), 0)
		tool(c'create', parent, c'5', c'3145728', c'4096', 0)
		simple(c'restore-auto', c'/root/saved.vmap', &char(nil), 1)
		missing(c'/dev/mapper/vinix2') // Conflict in a later slot cannot create a prefix.
		simple(c'remove', c'/dev/mapper/vinix5', &char(nil), 0)
		simple(c'restore-auto', c'/root/saved.vmap', &char(nil), 0)
		kept := status(c'/dev/mapper/vinix5').generation
		simple(c'remove', c'/dev/mapper/vinix2', &char(nil), 0)
		simple(c'restore', parent, c'/root/saved.vmap', 0)
		check(status(c'/dev/mapper/vinix5').generation == kept, c'resume keeps existing mapping')
		view_data()
		check(C.unlink(c'/dev/volume-plan-alias') == 0 && C.unlink(c'/dev/volume-plan-link') == 0, c'alias fixture cleanup')
		allocation_trace(c'/proc/allocstart', false)
		cycles(parent, 200)
		mut before := Heap{}; heap_snapshot(mut before)
		cycles(parent, 200)
		mut after := Heap{}; heap_snapshot(mut after)
		mut retained := before.count != after.count || after.large > before.large
		for i := 0; i < before.count; i++ {
			C.printf(c'PLAN RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
			if before.sizes[i] != after.sizes[i] || after.live[i] > before.live[i] { retained = true }
		}
		if retained {
			allocation_trace(c'/proc/allocsites', true)
		}
		check(!retained, c'heap retention')
		simple(c'save', parent, c'/etc/vinix/volumes.vmap', 0)
		plan := C.open(c'/root/saved.vmap', C.O_RDONLY); check(plan >= 0, c'open exported plan')
		mut bytes := [2112]u8{}
		size := C.read(plan, &bytes[0], 2112)
		check(size >= 128 && size <= 2112 && C.close(plan) == 0, c'export plan bytes')
		C.printf(c'PLAN FILE ')
		for i := i64(0); i < size; i++ { C.printf(c'%02x', u32(bytes[i])) }
		C.printf(c'\n')
		phase := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(phase >= 0 && C.write(phase, c'1', 1) == 1 && C.fsync(phase) == 0 && C.close(phase) == 0, c'persist reboot phase')
		directory := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY)
		check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist reboot phase directory')
	}
}

@[export: 'main']
pub fn entry(_argc i32, _argv &&char) i32 {
	unsafe { C.setbuf(C.stdout, nil) }
	$if amd64 {
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		check(serial >= 0 && C.dup2(serial, 1) == 1 && C.dup2(serial, 2) == 2 && C.close(serial) == 0, c'serial console')
		if C.getpid() == 1 {
			unsafe {
				arguments := [&char(c'/bin/sh'), &char(c'/usr/libexec/volume-test-init'), &char(nil)]!
				C.execv(c'/bin/sh', &arguments[0])
			}
			check(false, c'exec packaged init')
		}
	}
	parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
	C.printf(c'PLAN START\n')
	warm_image()
	phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 { first_boot(parent) }
	else {
		C.close(phase)
		view_data()
		actual := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		check(C.getppid() == 1 && status(c'/dev/mapper/vinix2').disk_id == status(actual).disk_id, c'init restored reordered physical disk')
		C.printf(c'PLAN BOOT RESTORED\n')
		before := status(c'/dev/mapper/vinix2').generation
		simple(c'boot-restore', unsafe { &char(nil) }, unsafe { &char(nil) }, 0)
		check(status(c'/dev/mapper/vinix2').generation == before, c'reboot restore idempotence')
	}
	C.printf(c'PLAN DONE\n')
	for { C.pause() }
	return 0
}
